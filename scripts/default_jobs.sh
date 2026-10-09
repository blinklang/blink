#!/bin/sh
# Print the default worker count for the parallel gate stages.
#
# On an open machine take half the CPUs, so a sweep that forks
# timeout -> blink -> cc per file leaves room for everything else. When a
# cgroup CPU quota or an affinity mask already holds this process to fewer
# CPUs than the machine has (nproc < nproc --all, as under
# blink-gates.slice), that limit has already set the room aside, and
# halving it again leaves half the allowed CPUs idle.
n=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)
all=$(nproc --all 2>/dev/null || echo "$n")
if [ "$n" -lt "$all" ]; then
    j=$n
else
    j=$((n / 2))
fi
[ "$j" -lt 1 ] && j=1
echo "$j"
