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
    local n=${1%[KMGT]}
    case "$1" in
        infinity) ;;
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
        for mem in 12G 2G 512M infinity; do
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

for bad_arg in "" 0 -1 x; do
    if ./scripts/inner_jobs.sh $bad_arg > /dev/null 2>&1; then
        bad "inner_jobs.sh accepted [$bad_arg]"
    fi
done

# Only default_jobs.sh reads the CPU count; any other site would size a
# fan-out from the CPUs and not from the budget. bench_edit_loop.sh only
# prints it.
while IFS= read -r hit; do
    case "$hit" in
        scripts/default_jobs.sh:* | scripts/test_gate_budget.sh:* | scripts/bench_edit_loop.sh:*'echo "# cc'*) ;;
        *) bad "a gate site reads the CPU count itself, not the budget: $hit" ;;
    esac
done < <(grep -nHE '\$\( *nproc([^a-z_-]|$)|hw\.ncpu' scripts/*.sh Taskfile.yml)

# Each task body that runs a fan-out sets GC_MARKERS and BLINK_JOBS for its
# workers: Boehm starts one marker thread per CPU in each process, and a test
# binary that runs its own per-module build starts one cc per CPU.
awk '
    /^  [A-Za-z0-9_:-]+:[[:space:]]*$/ { flush(); name = $1; body = ""; next }
    { body = body "\n" $0 }
    function flush() {
        if (name == "") return
        if (body ~ /parallel (-j|--joblog)|blink test tests\//) {
            if (body !~ /GC_MARKERS=/) print name " fans out with no GC_MARKERS"
            if (body !~ /BLINK_JOBS=/) print name " fans out with no BLINK_JOBS"
        }
    }
    END { flush() }
' Taskfile.yml > "$WORK/fanout.txt"
while IFS= read -r line; do bad "Taskfile.yml: $line"; done < "$WORK/fanout.txt"

if [ "$fail" = 0 ]; then
    echo "test_gate_budget: PASS"
fi
exit "$fail"
