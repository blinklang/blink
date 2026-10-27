#!/bin/bash
# Proves the gate's one worker budget: scripts/default_jobs.sh gives a count B
# that neither the CPUs nor the gate's memory cap is short of, and
# scripts/inner_jobs.sh splits B between the workers of a stage so that no
# layer multiplies another. Runs the scripts with a fake nproc at 1, 4, 12 and
# 64 CPUs. Also proves that only default_jobs.sh reads the CPU count, and that
# each Taskfile task that fans out sets GC_MARKERS and BLINK_JOBS for its
# workers. See docs/build/gate-memory-budget.md.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0
bad() { echo "test_gate_budget: FAIL $*"; fail=1; }

mkdir -p "$WORK/bin"
cat > "$WORK/bin/nproc" <<'EOF'
#!/bin/sh
[ "${1:-}" = --all ] && { echo "$FAKE_NPROC_ALL"; exit 0; }
echo "$FAKE_NPROC"
EOF
chmod +x "$WORK/bin/nproc"

# kib <size>: KiB of a systemd size, or nothing for infinity.
kib() {
    local u=${1^^}
    local n=${u%[KMGT]}
    case "$u" in
        INFINITY) ;;
        *K) echo "$n" ;;
        *M) echo $((n * 1024)) ;;
        *G) echo $((n * 1024 * 1024)) ;;
        *T) echo $((n * 1024 * 1024 * 1024)) ;;
        *) echo $(((n + 1023) / 1024)) ;;
    esac
}

# budget <cpus> <all cpus> <gate memory> <worker memory> <script> [<arg>]
budget() {
    local cpus=$1 all=$2 mem=$3 per=$4
    shift 4
    PATH="$WORK/bin:$PATH" FAKE_NPROC=$cpus FAKE_NPROC_ALL=$all \
        BLINK_GATE_MEMORY_MAX=$mem BLINK_GATE_WORKER_MEMORY=$per "$@"
}

for cpus in 1 4 12 64; do
    # all = cpus: an open machine; all = 2 x cpus: a CPU quota, as in the slice.
    for all in "$cpus" "$((cpus * 2))"; do
        for mem in 12G 2G 512m infinity; do
            for per in 1G 2G infinity; do
                case_="cpus=$cpus all=$all gate=$mem worker=$per"
                b=$(budget "$cpus" "$all" "$mem" "$per" ./scripts/default_jobs.sh)
                case "$b" in '' | *[!0-9]* | 0) bad "$case_: default_jobs gave [$b]"; continue ;; esac
                if [ "$cpus" -lt "$all" ]; then c=$cpus; else c=$((cpus / 2)); fi
                [ "$c" -lt 1 ] && c=1
                m=$c
                gk=$(kib "$mem")
                wk=$(kib "$per")
                if [ -n "$gk" ] && [ -n "$wk" ]; then
                    m=$((gk / wk))
                    [ "$m" -lt 1 ] && m=1
                fi
                want=$((c < m ? c : m))
                [ "$b" = "$want" ] || bad "$case_: default_jobs gave $b, want min(cpu $c, memory $m) = $want"
                # Every worker count a caller may pick, up to past the budget.
                for w in 1 2 3 $((b / 2)) "$b" $((b + 1)) $((b * 3)); do
                    [ "$w" -ge 1 ] || continue
                    i=$(budget "$cpus" "$all" "$mem" "$per" ./scripts/inner_jobs.sh "$w")
                    case "$i" in '' | *[!0-9]* | 0) bad "$case_: inner_jobs $w gave [$i]"; continue ;; esac
                    want_i=$((b / w))
                    [ "$want_i" -lt 1 ] && want_i=1
                    [ "$i" = "$want_i" ] || bad "$case_: inner_jobs $w gave $i, want max(1, $b / $w) = $want_i"
                    cap=$((w > b ? w : b))
                    [ $((w * i)) -le "$cap" ] ||
                        bad "$case_: $w workers x $i inner jobs = $((w * i)), over the budget $cap"
                done
            done
        done
    done
done

# The defaults: no BLINK_GATE_* in the env gives a 12G gate and 1G per worker.
b=$(PATH="$WORK/bin:$PATH" FAKE_NPROC=64 FAKE_NPROC_ALL=64 env -u BLINK_GATE_MEMORY_MAX -u BLINK_GATE_WORKER_MEMORY ./scripts/default_jobs.sh)
[ "$b" = 12 ] || bad "64 open CPUs with the default caps gave $b workers, want 12 (12G / 1G)"

# A caller's BLINK_JOBS may lower a worker's share but not raise it: a
# BLINK_JOBS from a login shell would otherwise multiply every fan-out again.
# 64 open CPUs, 12G / 2G: B = 6, so each of 2 workers gets 3.
share() { BLINK_JOBS=$1 budget 64 64 12G 2G ./scripts/inner_jobs.sh 2; }
[ "$(share 2)" = 2 ] || bad "a caller's BLINK_JOBS=2 under a share of 3 gave $(share 2), want 2"
[ "$(share 24)" = 3 ] || bad "a caller's BLINK_JOBS=24 over a share of 3 gave $(share 24), want 3"
for junk in "" 0 x 08; do
    [ "$(share "$junk")" = 3 ] || bad "a caller's BLINK_JOBS=[$junk] gave $(share "$junk"), want the share 3"
done

# A leading zero must not read as octal: 08 is 8.
got=$(budget 64 64 64G 08G ./scripts/default_jobs.sh 2>&1)
[ "$got" = 8 ] || bad "a worker size of 08G gave [$got], want 8"

# A gate size default_jobs.sh cannot read drops the memory term, so it must say so.
err=$(budget 64 64 4.5G 1G ./scripts/default_jobs.sh 2>&1 >/dev/null)
case "$err" in *BLINK_GATE_MEMORY_MAX*) ;; *) bad "a gate size of 4.5G gave no notice on stderr [$err]" ;; esac
err=$(budget 64 64 infinity 1G ./scripts/default_jobs.sh 2>&1 >/dev/null)
[ -z "$err" ] || bad "a gate size of infinity gave a notice [$err]"

for bad_arg in "" 0 -1 x 08; do
    if ./scripts/inner_jobs.sh $bad_arg > /dev/null 2>&1; then
        bad "inner_jobs.sh accepted [$bad_arg]"
    fi
done

# Only default_jobs.sh reads the CPU count; any other site would size a
# fan-out from the CPUs and not from the budget. bench_edit_loop.sh is not a
# gate script: it only prints the count.
cpu_read='(\$\(|`) *(command +)?nproc([^a-z_-]|$)|_NPROCESSORS|numCPU|hw\.ncpu|/proc/cpuinfo'
while IFS= read -r hit; do
    case "$hit" in
        scripts/default_jobs.sh:* | scripts/test_gate_budget.sh:* | scripts/bench_edit_loop.sh:*) ;;
        *) bad "a gate site reads the CPU count itself, not the budget: $hit" ;;
    esac
done < <(grep -nHE "$cpu_read" scripts/*.sh Taskfile.yml)
for probe in 'n=`nproc`' 'n=$(getconf _NPROCESSORS_ONLN)' 'n={{numCPU}}' 'n=$(command nproc)'; do
    printf '%s\n' "$probe" | grep -qE "$cpu_read" || bad "the CPU-count check misses [$probe]"
done

# Each fan-out line in a Taskfile task sets GC_MARKERS and BLINK_JOBS for its
# workers, on the line itself or through an export earlier in the same task:
# Boehm starts one marker thread per CPU in each process, and a test binary
# that runs its own per-module build starts one cc per CPU. Each line is
# checked, so one fan-out that sets them does not cover the next one.
fanout_check() {
    awk '
        /^  [A-Za-z0-9_:-]+:[[:space:]]*$/ { name = $1; bj = 0; gc = 0; next }
        /^[[:space:]]*#/ { next }
        {
            line = $0
            sub(/[[:space:]]#.*$/, "", line)
            if (line ~ /parallel +(-j|--joblog|--halt)|--parallel|xargs +-P/) {
                if (!gc && line !~ /GC_MARKERS=/) print name NR " fans out with no GC_MARKERS"
                if (!bj && line !~ /BLINK_JOBS=/) print name NR " fans out with no BLINK_JOBS"
            }
            if (line ~ /export[^#]*BLINK_JOBS/) bj = 1
            if (line ~ /export[^#]*GC_MARKERS/) gc = 1
        }
    ' "$1"
}
fanout_check Taskfile.yml > "$WORK/fanout.txt"
while IFS= read -r line; do bad "Taskfile.yml: $line"; done < "$WORK/fanout.txt"
# The check itself: a second fan-out line, or knobs named only in a comment,
# must not pass.
cat > "$WORK/Taskfile.yml" <<'TASKS'
tasks:
  two:
    cmds:
      - BLINK_JOBS=1 GC_MARKERS=1 parallel -j 4 a ::: x
      - parallel -j 4 b ::: x
  comment:
    cmds:
      # BLINK_JOBS= GC_MARKERS= set by the caller
      - parallel --halt never -j 4 c ::: x
  exported:
    cmds:
      - |
        BLINK_JOBS=$(./scripts/inner_jobs.sh 4) || exit 2
        export BLINK_JOBS GC_MARKERS=1
        parallel -j 4 d ::: x
        blink test tests/ --parallel 4
TASKS
got=$(fanout_check "$WORK/Taskfile.yml" | cut -d: -f1 | sort -u | tr '\n' ' ')
[ "$got" = "comment two " ] || bad "the fan-out check flagged [$got], want [comment two ]"

if [ "$fail" = 0 ]; then
    echo "test_gate_budget: PASS"
fi
exit "$fail"
