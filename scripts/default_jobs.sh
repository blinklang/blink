#!/bin/sh
# Print the gate's worker budget: the most workers that all of a gate's
# parallel stages may run at once. Each fan-out takes its worker count from
# here, and scripts/inner_jobs.sh splits the count further for the processes
# that each worker starts, so no layer multiplies another. This is the only
# gate script that reads the CPU count. See docs/build/gate-memory-budget.md.
#
# CPUs: on an open machine take half the CPUs, so a sweep that forks
# timeout -> blink -> cc per file leaves room for everything else. When a
# cgroup CPU quota or an affinity mask already holds this process to fewer
# CPUs than the machine has (nproc < nproc --all, as under
# blink-gates.slice), that limit has already set the room aside, and
# halving it again leaves half the allowed CPUs idle.
#
# Memory: no more workers than the gate's memory cap holds at
# BLINK_GATE_WORKER_MEMORY each, so a machine with many CPUs does not run the
# gate into its cap. "infinity" for either size drops this limit.
#
# Env:
#   BLINK_GATE_MEMORY_MAX=12G      the gate's memory cap, as scripts/capped.sh sets it
#   BLINK_GATE_WORKER_MEMORY=1G    memory to allow for each worker
n=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)
all=$(nproc --all 2>/dev/null || echo "$n")
if [ "$n" -lt "$all" ]; then
    j=$n
else
    j=$((n / 2))
fi

# kib <systemd size>: KiB, or nothing for infinity or a size with no number.
kib() {
    num=${1%[KkMmGgTt]}
    case "$num" in '' | *[!0-9]*) return ;; esac
    # Shell arithmetic reads a leading 0 as octal.
    num=${num#"${num%%[!0]*}"}
    num=${num:-0}
    case "$1" in
        *[Kk]) echo "$num" ;;
        *[Mm]) echo $((num * 1024)) ;;
        *[Gg]) echo $((num * 1024 * 1024)) ;;
        *[Tt]) echo $((num * 1024 * 1024 * 1024)) ;;
        *) echo $(((num + 1023) / 1024)) ;;
    esac
}
# size <name> <value>: KiB of the value. systemd also takes sizes such as 4.5G
# or 50%, which give no number here; say so, as the gate then caps at that
# size while the workers fill the CPUs.
size() {
    s=$(kib "$2")
    [ -z "$s" ] && [ "$2" != infinity ] &&
        echo "default_jobs: cannot read $1=$2 (use K, M, G or T); the worker budget has no memory limit" >&2
    echo "$s"
}
gate=$(size BLINK_GATE_MEMORY_MAX "${BLINK_GATE_MEMORY_MAX:-12G}")
worker=$(size BLINK_GATE_WORKER_MEMORY "${BLINK_GATE_WORKER_MEMORY:-1G}")
if [ -n "$gate" ] && [ -n "$worker" ] && [ "$worker" -gt 0 ]; then
    m=$((gate / worker))
    [ "$m" -lt "$j" ] && j=$m
fi
[ "$j" -lt 1 ] && j=1
echo "$j"
