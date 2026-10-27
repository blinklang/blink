#!/bin/bash
# Run a command under one gate's memory and process caps. A runaway gate then
# hits its own caps, and the kernel's global OOM killer does not kill other
# programs to free memory for it.
# See docs/build/gate-memory-budget.md for the numbers.
#
#   scripts/capped.sh [--name <name>] <command> [<arg> ...]
#
# --name names the scope unit, blink-gate-<name>-<pid>-<time>.scope; without
# it the command's own name does. Only a Taskfile dispatcher passes --name.
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
# Env:
#   BLINK_GATE_CAP=0                    run in place, uncapped (a machine that caps gates another way)
#   BLINK_GATE_MEMORY_MAX=12G           memory cap of the run (systemd size: K, M, G, T)
#   BLINK_GATE_TASKS_MAX=1024           process and thread cap of the run
#   BLINK_GATE_SWAP_MAX                 swap cap of the run; unset leaves swap to the slice
#   BLINK_GATE_SLICE=blink-gates.slice  user slice that holds the run's scope
set -u

mem=${BLINK_GATE_MEMORY_MAX:-12G}
tasks=${BLINK_GATE_TASKS_MAX:-1024}
swap=${BLINK_GATE_SWAP_MAX:-}
slice=${BLINK_GATE_SLICE:-blink-gates.slice}

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

# Runs inside the new scope: run the command, then read the scope's own event
# counters while the scope still exists, so a kill by the cap reads as one.
if [ "${1:-}" = --inner ]; then
    shift
    "$@"
    rc=$?
    IFS=: read -r _ _ cg < /proc/self/cgroup
    dir=/sys/fs/cgroup$cg
    oom=$(read_event "$dir/memory.events" oom_kill)
    at_max=$(read_event "$dir/memory.events" max)
    forks=$(read_event "$dir/pids.events" max)
    if [ "$oom" != 0 ]; then
        if [ "$at_max" != 0 ]; then
            notice "the run hit its memory cap (MemoryMax=$mem) and the OOM killer killed $oom of its processes; exit $rc"
        else
            notice "the OOM killer killed $oom of the run's processes below its memory cap (MemoryMax=$mem), so the slice or the machine ran out; exit $rc"
        fi
    fi
    if [ "$forks" != 0 ]; then
        notice "the run hit its process cap (TasksMax=$tasks): $forks forks failed; exit $rc"
    fi
    # A runaway leaves children that would hold the scope open; end them.
    if [ "$oom" != 0 ] || [ "$forks" != 0 ]; then
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            others=0
            while read -r pid; do
                [ "$pid" = "$$" ] && continue
                kill -9 "$pid" 2>/dev/null
                others=1
            done < "$dir/cgroup.procs"
            [ "$others" = 0 ] && break
        done
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

if [ "${BLINK_GATE_CAP:-1}" = 0 ]; then
    notice "BLINK_GATE_CAP=0, so this run has no memory or process cap"
    export BLINK_GATE_SCOPE=off
    exec "$@"
fi

export BLINK_GATE_MEMORY_MAX=$mem BLINK_GATE_TASKS_MAX=$tasks

# OOMPolicy=continue: systemd would otherwise stop the scope on the first OOM
# kill, and the report below would die with it.
props=(-p "MemoryMax=$mem" -p "TasksMax=$tasks" -p OOMPolicy=continue)
[ -n "$swap" ] && props+=(-p "MemorySwapMax=$swap")
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
        *) echo $((n / 1024)) ;;
    esac
}

kib=$(size_kib "$mem")
# RLIMIT_NPROC counts every process and thread of the user, not only this run,
# so the cap is what runs now plus the run's share.
procs=
uid=$(id -u)
if [ -d /proc/self/task ]; then
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
case "$running" in '' | *[!0-9]* | 0) ;; *) procs=$((running + tasks)) ;; esac

limits=()
[ -n "$kib" ] && limits+=("address space $mem per process")
[ -n "$procs" ] && limits+=("$procs processes for the user")

if command -v prlimit >/dev/null 2>&1 && [ ${#limits[@]} -gt 0 ]; then
    args=()
    [ -n "$kib" ] && args+=(--as=$((kib * 1024)))
    [ -n "$procs" ] && args+=(--nproc="$procs")
    if prlimit "${args[@]}" "$BASH" -c : 2>/dev/null; then
        notice "no systemd user scope, so prlimit caps this run: $(join "${limits[@]}")"
        export BLINK_GATE_SCOPE=prlimit
        exec prlimit "${args[@]}" -- "$@"
    fi
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
exec "$@"
