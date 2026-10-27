#!/bin/bash
# Run a command under one gate's memory and process caps. A runaway gate then
# hits its own caps, and the kernel's global OOM killer does not kill other
# programs to free memory for it.
# See docs/build/gate-memory-budget.md for the numbers.
#
#   scripts/capped.sh [--name <name>] <command> [<arg> ...]
#   scripts/capped.sh --child [--timeout <seconds>] [--report <file>] <command> [<arg> ...]
#
# --name names the scope unit, blink-gate-<name>-<pid>-<time>.scope; without
# it the command's own name does. Only a Taskfile dispatcher passes --name.
#
# --child runs one test child (a test binary or a fixture build) under caps of
# its own inside the gate run, so a runaway child dies alone and fails as one
# test. When the child hits a cap, a line on stderr names it. --timeout sets
# the child's time limit for this call. --report <file> gets the line of the
# cap that ended a failed child, and is empty after any other run, so a caller
# reads the reason without parsing the child's output.
#
# Each heavy Taskfile task re-runs itself through this script. The capped run
# exports BLINK_GATE_SCOPE, and a call that finds it set runs the command in
# place, so nested tasks never stack caps.
#
# The first way that works caps the run:
#   1. a systemd user scope in BLINK_GATE_SLICE, or a plain user scope when
#      that slice has no unit
#   2. prlimit: address space per process, process count for the user
#   3. ulimit -v and -u, the same limits from the shell
#   4. none: the run goes on uncapped. A missing cap never fails the task
# Ways 2 to 4 print a one-line notice.
#
# A child gets a cgroup of its own below the gate's scope when systemd
# delegates the scope; else prlimit or ulimit caps its address space per
# process, and no line names that cap when the child hits it. The gate prints
# the one notice for that fallback, not each child. Every way gets the time
# limit when a timeout command exists.
#
# Env:
#   BLINK_GATE_CAP=0                    run in place, uncapped (a machine that caps gates another way)
#   BLINK_GATE_MEMORY_MAX=12G           memory cap of the run (systemd size: K, M, G, T)
#   BLINK_GATE_TASKS_MAX=1024           process and thread cap of the run
#   BLINK_GATE_SWAP_MAX=2G              swap cap of the run
#   BLINK_GATE_SLICE=blink-gates.slice  user slice that holds the run's scope
#   BLINK_CHILD_CAP=0                   run each child in place, with no memory or process cap
#   BLINK_CHILD_MEMORY_MAX=2G           memory cap of one child
#   BLINK_CHILD_TASKS_MAX=256           process and thread cap of one child
#   BLINK_CHILD_SWAP_MAX=0              swap cap of one child; infinity leaves swap to the gate
#   BLINK_CHILD_TIMEOUT=600             time limit of one child in seconds; 0 sets none
#   BLINK_CHILD_KILL_AFTER=10           seconds from SIGTERM to SIGKILL at the time limit
set -u

mem=${BLINK_GATE_MEMORY_MAX:-12G}
tasks=${BLINK_GATE_TASKS_MAX:-1024}
# A run with no swap cap pages out for minutes before the memory cap kills it,
# and the plain-scope fallback has no slice to cap its swap.
swap=${BLINK_GATE_SWAP_MAX:-2G}
slice=${BLINK_GATE_SLICE:-blink-gates.slice}
child_mem=${BLINK_CHILD_MEMORY_MAX:-2G}
child_tasks=${BLINK_CHILD_TASKS_MAX:-256}
# A child at its cap must die at once, not page out to the one swap cap that
# all of the gate's children share.
child_swap=${BLINK_CHILD_SWAP_MAX:-0}
child_timeout=${BLINK_CHILD_TIMEOUT:-600}
child_kill_after=${BLINK_CHILD_KILL_AFTER:-10}

notice() { echo "capped.sh: $*" >&2; }

# Only builtins below: after a fork loop hits the task cap, a fork can fail.
read_event() {
    # read_event <file> <key>: the counter, or 0
    local k v
    [ -r "$1" ] || { echo 0; return; }
    while read -r k v; do
        [ "$k" = "$2" ] && { echo "$v"; return; }
    done < "$1"
    echo 0
}

# own_events <dir> <file>: the file that counts only the events of <dir>'s own
# limit. The plain file also counts each child cgroup's events.
own_events() {
    if [ -r "$1/$2.local" ]; then echo "$1/$2.local"; else echo "$1/$2"; fi
}

# end_procs <cgroup dir> [<pid to keep>]: kill each process left in the cgroup.
end_procs() {
    local pid others
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        others=0
        while read -r pid; do
            [ "$pid" = "${2:-}" ] && continue
            kill -9 "$pid" 2>/dev/null
            others=1
        done < "$1/cgroup.procs"
        [ "$others" = 0 ] && return
    done
}

join() {
    local out=$1
    shift
    for x in "$@"; do out="$out, $x"; done
    echo "$out"
}

# size_kib <systemd size>: KiB, or nothing when the size has no number.
size_kib() {
    local n=${1%[KkMmGgTt]} u=${1: -1}
    case "$n" in '' | *[!0-9]*) return ;; esac
    case "$u" in
        K | k) echo "$n" ;;
        M | m) echo $((n * 1024)) ;;
        G | g) echo $((n * 1024 * 1024)) ;;
        T | t) echo $((n * 1024 * 1024 * 1024)) ;;
        *) echo $(((n + 1023) / 1024)) ;;
    esac
}

# rlimit_plan <size> <tasks>: sets kib, procs and limits (their text) for the
# prlimit and ulimit ways.
rlimit_plan() {
    local os uid running u
    os=$(uname -s 2>/dev/null)
    kib=
    # Darwin takes ulimit -v and does not hold a process to it.
    [ "$os" = Darwin ] || kib=$(size_kib "$1")
    # RLIMIT_NPROC counts every process and thread of the user, not only this
    # run, so the cap is what runs now plus the run's share.
    procs=
    uid=$(id -u)
    if [ "$os" = Linux ]; then
        # Linux counts threads against RLIMIT_NPROC, and ps -L lists them.
        running=$(ps -L -u "$uid" -o lwp= 2>/dev/null | wc -l)
    else
        # BSD and macOS count processes; there ps -L lists keywords, not threads.
        running=0
        while read -r u; do
            [ "$u" = "$uid" ] && running=$((running + 1))
        done < <(ps -ax -o uid= 2>/dev/null)
    fi
    running=${running//[[:space:]]/}
    # A count of 0 means ps failed; a cap such as "infinity" sets no count.
    case "$running" in '' | *[!0-9]* | 0) running= ;; esac
    case "$2" in '' | *[!0-9]*) running= ;; esac
    [ -n "$running" ] && procs=$((running + $2))
    limits=()
    [ -n "$kib" ] && limits+=("address space $1 per process")
    [ -n "$procs" ] && limits+=("$procs processes for the user")
}

# prlimit_args: the prlimit flags for the plan, or failure when prlimit cannot
# apply it.
prlimit_args() {
    command -v prlimit >/dev/null 2>&1 && [ ${#limits[@]} -gt 0 ] || return 1
    plargs=()
    [ -n "$kib" ] && plargs+=(--as=$((kib * 1024)))
    [ -n "$procs" ] && plargs+=(--nproc="$procs")
    prlimit "${plargs[@]}" "$BASH" -c : 2>/dev/null
}

# timeout_tool: the coreutils timeout, as Darwin's Homebrew names it too.
timeout_tool() {
    command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null
}

# child_notice: the gate's one notice for a child cap that is not a cgroup of
# its own, and the export that tells each child which way to take: prlimit or
# ulimit for the address space, or none. A child gets no process cap of its
# own this way: RLIMIT_NPROC counts every process of the user, so a sibling
# that starts after a child would eat that child's share. The gate's process
# cap still holds.
child_notice() {
    local os kib
    if [ "${BLINK_CHILD_CAP:-1}" = 0 ]; then
        export BLINK_CHILD_CAP_MODE=none
        return
    fi
    os=$(uname -s 2>/dev/null)
    kib=
    # Darwin takes ulimit -v and does not hold a process to it.
    [ "$os" = Darwin ] || kib=$(size_kib "$child_mem")
    if [ -z "$kib" ] && [ "$os" = Darwin ]; then
        export BLINK_CHILD_CAP_MODE=none
        notice "each child gets no memory or process cap of its own: this machine has no cgroup for it, and no address space cap holds here"
    elif [ -z "$kib" ]; then
        export BLINK_CHILD_CAP_MODE=none
        notice "each child gets no memory or process cap of its own: this machine has no cgroup for it, and BLINK_CHILD_MEMORY_MAX=$child_mem sets no address space cap"
    else
        if command -v prlimit >/dev/null 2>&1 && prlimit --as=$((kib * 1024)) "$BASH" -c : 2>/dev/null; then
            export BLINK_CHILD_CAP_MODE=prlimit
        else
            export BLINK_CHILD_CAP_MODE=ulimit
        fi
        notice "each child gets an address space cap of $child_mem per process, not a cgroup of its own, so no line names a memory or process cap it hits"
    fi
    [ "$child_timeout" = 0 ] || timeout_tool >/dev/null || notice "no timeout command, so a child has no time limit"
}

# --- One child ------------------------------------------------------------------

# report_child <rc> <elapsed> <limit> <gate forks before>: print one line per
# cap the child hit, the cap that ended it first. A child that failed keeps
# that first line in the --report file; a child that passed hit no cap that
# matters to it.
report_child() {
    local lines=() oom own_oom forks gate_forks=0 which
    if [ -n "$kid" ]; then
        oom=$(read_event "$kid/memory.events" oom_kill)
        own_oom=$(read_event "$kid/memory.events" oom)
        forks=$(read_event "$kid/pids.events.local" max)
        which="its process cap (TasksMax=$child_tasks)"
        if [ -r "$kid/pids.events.local" ]; then
            gate_forks=$(($(read_event "$dir/pids.events.local" max) - $4))
        else
            # Before Linux 6.13, pids.events counts a refused fork in the
            # forker's cgroup, whichever cap refused it.
            forks=$(read_event "$kid/pids.events" max)
            which="a process cap (its TasksMax=$child_tasks or the gate's TasksMax=$tasks)"
        fi
        if [ "$oom" != 0 ] && [ "$own_oom" != 0 ]; then
            lines+=("the child hit its memory cap (MemoryMax=$child_mem) and the OOM killer killed $oom of its processes; exit $1")
        fi
    fi
    # timeout exits 124 at the limit, or 137 when SIGTERM did not end the
    # child. A child can exit 124 itself, and 137 is also an OOM kill, so
    # either counts only when the time is spent.
    if [ "$3" != 0 ] && [ "$2" -ge "$3" ] && { [ "$1" = 124 ] || [ "$1" = 137 ]; }; then
        lines+=("the child ran past its time limit (${3}s) and was killed; exit $1")
    fi
    if [ -n "$kid" ]; then
        if [ "$oom" != 0 ] && [ "$own_oom" = 0 ]; then
            lines+=("the child lost $oom processes to the OOM killer below its memory cap (MemoryMax=$child_mem), so the gate or the machine ran out; exit $1")
        fi
        if [ "$forks" != 0 ]; then
            lines+=("the child hit $which: $forks forks failed; exit $1")
        fi
    fi
    local l
    for l in ${lines[@]+"${lines[@]}"}; do notice "$l"; done
    if [ -n "$report" ] && [ "$1" != 0 ] && [ ${#lines[@]} -gt 0 ]; then
        echo "capped.sh: ${lines[0]}" > "$report"
    fi
    # The gate's count is shared, so a sibling may own these failures: a
    # child that failed names them, but not as its reason.
    if [ "$gate_forks" -gt 0 ] && [ "$1" != 0 ]; then
        notice "the gate refused $gate_forks forks at its process cap (TasksMax=$tasks) while this child ran; exit $1"
    fi
}

# launch <command...>: run the command in the background and wait for it, so
# the trap in run_child can stop it. Job control puts it in a process group of
# its own and keeps its SIGINT at the default; a shell without job control
# makes a background command ignore SIGINT. A process group that is not the
# terminal's stops when it reads the terminal, so the child reads nothing from
# it. The wait's stderr goes nowhere, so bash prints no job line
# ("Segmentation fault ...") into the child's log.
launch() {
    set -m
    if [ -t 0 ]; then "$@" < /dev/null & else "$@" & fi
    pid=$!
    set +m
    wait "$pid" 2>/dev/null
    rc=$?
}

# end_kid: kill what is left in the child's cgroup and remove it. A process
# the child left behind would hold the cgroup open.
end_kid() {
    [ -n "$kid" ] || return
    if [ -w "$kid/cgroup.kill" ]; then
        echo 1 > "$kid/cgroup.kill"
    else
        end_procs "$kid"
    fi
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        rmdir "$kid" 2>/dev/null && break
        sleep 0.05 2>/dev/null || sleep 1
    done
}

# stop_child <signal>: a signal stopped the wrapper, so stop the child, then
# die by the same signal. timeout runs in its own process group, so a
# terminal's SIGINT reaches only this script; without this the child would
# run on to its time limit. A shell that waits for this script goes on after
# a child that exits 130, but stops after one that SIGINT killed.
stop_child() {
    # A signal just after the fork comes before pid=$!.
    local p=${pid:-${!:-}}
    if [ -n "$p" ]; then
        # The child's process group too: it may not have moved into its
        # cgroup yet.
        kill -TERM -- "-$p" 2>/dev/null
        [ -n "$kid" ] && [ -w "$kid/cgroup.kill" ] && echo 1 > "$kid/cgroup.kill"
        wait "$p" 2>/dev/null
    fi
    end_kid
    trap - "$1"
    kill -"$1" "$$"
    exit $((128 + $(kill -l "$1")))
}

run_child() {
    local limit=$child_timeout tool start cg gate_forks=0 kib
    report=
    while :; do
        case "${1:-}" in
            --timeout) limit=${2:-}; shift 2 || shift ;;
            --report)
                report=${2:-}
                shift 2 || shift
                [ -n "$report" ] || { echo "capped.sh: --report takes a file" >&2; exit 2; }
                ;;
            *) break ;;
        esac
    done
    case "$limit" in '' | *[!0-9]*) echo "capped.sh: --timeout takes whole seconds, not [$limit]" >&2; exit 2 ;; esac
    [ $# -gt 0 ] || { echo "usage: capped.sh --child [--timeout <seconds>] [--report <file>] <command> [<arg> ...]" >&2; exit 2; }
    [ -z "$report" ] || : > "$report"

    tl=()
    if [ "$limit" != 0 ] && tool=$(timeout_tool); then
        tl=("$tool" -k "$child_kill_after" "$limit")
    else
        limit=0
    fi

    local mode=${BLINK_CHILD_CAP_MODE:-}
    [ "${BLINK_CHILD_CAP:-1}" = 0 ] && mode=none
    # A child of a child is already under its parent's caps.
    [ -n "${BLINK_CHILD_CAPPED:-}" ] && mode=none
    dir=
    if [ "$mode" = cgroup ]; then
        IFS=: read -r _ _ cg < /proc/self/cgroup
        dir=${BLINK_CHILD_CGROUP:-}
        # Only the gate's own processes may start a child cgroup: from inside
        # a child, the move would take the new child out of its parent's caps.
        [ "/sys/fs/cgroup$cg" = "$dir/gate" ] || mode=none
    fi
    if [ -z "$mode" ]; then
        # No gate run set the way: a direct call, so this call gives the notice.
        child_notice
        mode=$BLINK_CHILD_CAP_MODE
    fi
    export BLINK_CHILD_CAPPED=1

    pid=
    kid=
    trap 'stop_child HUP' HUP
    trap 'stop_child INT' INT
    trap 'stop_child TERM' TERM
    start=${EPOCHSECONDS:-$(date +%s)}
    case "$mode" in
        cgroup)
            kid=$dir/kids/c-$$
            # systemd's word for no cap is "infinity"; the cgroup file's is "max".
            if mkdir "$kid" 2>/dev/null &&
                echo "${child_mem/#infinity/max}" 2>/dev/null > "$kid/memory.max" &&
                echo "${child_tasks/#infinity/max}" 2>/dev/null > "$kid/pids.max"; then
                # With no swap account the file is missing; the gate said so once.
                if [ -e "$kid/memory.swap.max" ] && ! echo "${child_swap/#infinity/max}" 2>/dev/null > "$kid/memory.swap.max"; then
                    notice "could not set this child's swap cap (MemorySwapMax=$child_swap), so only the gate's swap cap holds it"
                fi
                gate_forks=$(read_event "$dir/pids.events.local" max)
                # The subshell moves itself, then execs; this script stays in
                # the gate's cgroup, so the cap's OOM kill never picks it.
                launch "$BASH" -c 'echo 0 2>/dev/null > "$1/cgroup.procs" ||
                    echo "capped.sh: could not move this child into its cgroup, so it runs uncapped" >&2
                    shift; exec "$@"' _ "$kid" ${tl[@]+"${tl[@]}"} "$@"
            else
                notice "could not make a cgroup for this child in $dir/kids, so it runs uncapped"
                rmdir "$kid" 2>/dev/null
                kid=
                launch ${tl[@]+"${tl[@]}"} "$@"
            fi
            ;;
        prlimit | ulimit)
            kib=$(size_kib "$child_mem")
            if [ -z "$kib" ]; then
                launch ${tl[@]+"${tl[@]}"} "$@"
            elif [ "$mode" = prlimit ]; then
                launch prlimit --as=$((kib * 1024)) -- ${tl[@]+"${tl[@]}"} "$@"
            else
                launch "$BASH" -c 'ulimit -v "$1" 2>/dev/null; shift; exec "$@"' _ "$kib" ${tl[@]+"${tl[@]}"} "$@"
            fi
            ;;
        *)
            launch ${tl[@]+"${tl[@]}"} "$@"
            ;;
    esac
    trap - HUP INT TERM
    report_child "$rc" "$(( ${EPOCHSECONDS:-$(date +%s)} - start ))" "$limit" "$gate_forks"
    end_kid
    exit "$rc"
}

if [ "${1:-}" = --child ]; then
    shift
    run_child "$@"
fi

# --- The gate run ---------------------------------------------------------------

# Runs inside the new scope: run the command, then read the scope's own event
# counters while the scope still exists, so a kill by the cap reads as one.
if [ "${1:-}" = --inner ]; then
    shift
    IFS=: read -r _ _ cg < /proc/self/cgroup
    dir=/sys/fs/cgroup$cg
    leaf=$dir
    # A delegated scope holds the gate in its leaf gate/ and each child in a
    # cgroup of its own under kids/. A cgroup that hands controllers to its
    # children may hold no process, so this script moves into gate/ first.
    if [ "${BLINK_CHILD_CAP_MODE:-}" = cgroup ]; then
        if mkdir -p "$dir/gate" "$dir/kids" &&
            echo 0 > "$dir/gate/cgroup.procs" &&
            echo "+memory +pids" > "$dir/cgroup.subtree_control" &&
            echo "+memory +pids" > "$dir/kids/cgroup.subtree_control"; then
            leaf=$dir/gate
            export BLINK_CHILD_CGROUP=$dir
            [ -e "$dir/kids/memory.swap.max" ] || [ "$child_swap" = infinity ] ||
                notice "this kernel keeps no swap account, so a child gets no swap cap of its own (MemorySwapMax=$child_swap), only the gate's"
        else
            child_notice
        fi
    fi
    # At the cap the kernel can kill a second process before the first
    # victim's memory is freed. A higher score makes that a process of the
    # command, never this script, which still has to write the report. A step
    # of 500, not the top score, keeps a run nested in another run (as in the
    # self-tests) above its own reporter too.
    adj=0
    read -r adj < /proc/self/oom_score_adj 2>/dev/null
    adj=$(( adj + 500 > 1000 ? 1000 : adj + 500 ))
    "$BASH" -c 'echo "$1" 2>/dev/null > /proc/self/oom_score_adj; shift; exec "$@"' _ "$adj" "$@"
    rc=$?
    # The scope's own limit, not a child's: a child's cap is the child's line.
    # The plain oom_kill also counts each child's kills at its own cap, so
    # only the scope's own oom count says that the run's cap fired.
    own_oom=$(read_event "$(own_events "$dir" memory.events)" oom)
    oom=$(read_event "$dir/memory.events" oom_kill)
    gate_oom=$(read_event "$leaf/memory.events" oom_kill)
    forks=$(read_event "$(own_events "$dir" pids.events)" max)
    # Before Linux 6.13, pids.events counts a refused fork in the forker's
    # cgroup, and the gate's processes are in its leaf.
    [ -r "$dir/pids.events.local" ] || forks=$(read_event "$leaf/pids.events" max)
    if [ "$own_oom" != 0 ] && [ "$leaf" = "$dir" ]; then
        notice "the run hit its memory cap (MemoryMax=$mem) and the OOM killer killed $oom of its processes; exit $rc"
    elif [ "$own_oom" != 0 ]; then
        notice "the run hit its memory cap (MemoryMax=$mem) and the OOM killer killed $gate_oom of the gate's own processes; a child it killed has a line of its own; exit $rc"
    elif [ "$gate_oom" != 0 ]; then
        notice "the OOM killer killed $gate_oom of the run's processes below its memory cap (MemoryMax=$mem), so the slice or the machine ran out; exit $rc"
    fi
    if [ "$forks" != 0 ]; then
        notice "the run hit its process cap (TasksMax=$tasks): $forks forks failed; exit $rc"
    fi
    # A runaway leaves children that would hold the scope open; end them.
    if [ "$own_oom" != 0 ] || [ "$gate_oom" != 0 ] || [ "$forks" != 0 ]; then
        end_procs "$leaf" "$$"
        [ -w "$dir/kids/cgroup.kill" ] && echo 1 > "$dir/kids/cgroup.kill"
    fi
    exit "$rc"
fi

name=
if [ "${1:-}" = --name ]; then
    name=${2:-}
    shift 2 || shift
fi
[ $# -gt 0 ] || { echo "usage: capped.sh [--name <name>] <command> [<arg> ...]" >&2; exit 2; }

if [ -n "${BLINK_GATE_SCOPE:-}" ]; then
    # In a capped run a dispatcher calls its body, not this script. A Task
    # before 3.47 ignores the cmd-level `if:` and would re-run the dispatcher
    # here, which execs task again, with no end.
    if [ -n "$name" ]; then
        echo "capped.sh: task $name ran its dispatcher inside its capped run; the Taskfile needs Task 3.47 or later" >&2
        exit 2
    fi
    exec "$@"
fi

# A new gate run is never inside a child's caps, even when this script runs
# from inside a child: the run sets these again for its own children.
unset BLINK_CHILD_CAPPED BLINK_CHILD_CGROUP BLINK_CHILD_CAP_MODE

if [ "${BLINK_GATE_CAP:-1}" = 0 ]; then
    notice "BLINK_GATE_CAP=0, so this run has no memory or process cap"
    export BLINK_GATE_SCOPE=off
    child_notice
    exec "$@"
fi

export BLINK_GATE_MEMORY_MAX=$mem BLINK_GATE_TASKS_MAX=$tasks

# OOMPolicy=continue: systemd would otherwise stop the scope on the first OOM
# kill, and the report below would die with it.
props=(-p "MemoryMax=$mem" -p "MemorySwapMax=$swap" -p "TasksMax=$tasks" -p OOMPolicy=continue)
# systemd 254 and later expand $VAR in the command line of a scope; the
# command must reach the shell as the caller wrote it.
if command -v systemd-run >/dev/null 2>&1 && systemd-run --help 2>/dev/null | grep -q -- --expand-environment; then
    props+=(--expand-environment=no)
fi

# Try the exact scope first: a box with no user bus, or with no memory or pids
# controller for the user, fails here, and systemd-run's own exit 1 would
# otherwise read as the command's.
scope_starts() {
    systemd-run --user --scope -q "$@" "${props[@]}" true >/dev/null 2>&1
}
if command -v systemd-run >/dev/null 2>&1 && scope_starts; then
    # Delegate=yes hands the scope's cgroup to the run, which makes one cgroup
    # per child below it; the gate's caps still hold over the children.
    if scope_starts -p Delegate=yes; then
        props+=(-p Delegate=yes)
        export BLINK_CHILD_CAP_MODE=cgroup
    else
        child_notice
    fi
    slice_args=(--slice="$slice")
    # systemd makes a slice on first use, with no limits; only a unit file or a
    # drop-in gives it the shared CPU and memory limits.
    unit_files=$(systemctl --user show -p FragmentPath -p DropInPaths --value "$slice" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$unit_files" ]; then
        notice "$slice has no unit, so this run gets a plain user scope with its own caps only"
        slice_args=()
    elif ! scope_starts "${slice_args[@]}"; then
        notice "$slice cannot hold a scope, so this run gets a plain user scope with its own caps only"
        slice_args=()
    fi
    [ -n "$name" ] || name=${1##*/}
    name=${name//[^A-Za-z0-9_-]/_}
    # EPOCHSECONDS needs bash 5.0.
    unit=blink-gate-$name-$$-${EPOCHSECONDS:-$(date +%s)}.scope
    export BLINK_GATE_SCOPE=$unit
    # --collect: a scope that ends failed would keep its name loaded. The
    # ${a[@]+...} form keeps an empty array legal under set -u before bash 4.4.
    exec systemd-run --user --scope -q --collect --unit="$unit" ${slice_args[@]+"${slice_args[@]}"} "${props[@]}" \
        bash "$0" --inner "$@"
fi

rlimit_plan "$mem" "$tasks"

if prlimit_args; then
    notice "no systemd user scope, so prlimit caps this run: $(join "${limits[@]}")"
    export BLINK_GATE_SCOPE=prlimit
    child_notice
    exec prlimit "${plargs[@]}" -- "$@"
fi

applied=()
[ -n "$kib" ] && ulimit -v "$kib" 2>/dev/null && applied+=("address space $mem per process")
[ -n "$procs" ] && ulimit -u "$procs" 2>/dev/null && applied+=("$procs processes for the user")
if [ ${#applied[@]} -gt 0 ]; then
    notice "no systemd user scope and no prlimit, so ulimit caps this run: $(join "${applied[@]}")"
    export BLINK_GATE_SCOPE=ulimit
else
    notice "no systemd user scope, prlimit or ulimit, so this run has no memory or process cap"
    export BLINK_GATE_SCOPE=none
fi
child_notice
exec "$@"
