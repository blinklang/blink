#!/bin/bash
# Compile and run every tests/test_*.bl independently and write
# build/corpus.json, with no fail-fast and no directory-mode pre-typecheck, so
# one broken file cannot hide the result of the others.
#
# The compiler under test is gen1 — the CURRENT source compiled by the pinned
# gen0. gen0 itself is a fixed binary, so a corpus run against it measures
# nothing about the tree and never moves.
#
#   scripts/corpus.sh [--only <list file>] [--no-lint] [--per-module-slice <list file>]
#
# Env:
#   CORPUS_COMPILER  dir holding blink/blinkc/libblink_std.* (default build/gen1)
#   CORPUS_JOBS      parallel workers (default: scripts/default_jobs.sh)
#   CORPUS_OUT       output JSON (default build/corpus.json)
#   CORPUS_PRELUDE_LIB  lib/ root each sandbox exposes as the prelude, passed
#                    through to corpus_one.sh (default: the compiler's own)
#   CORPUS_COMPILER_ARCHIVE  0 builds every file in one unit, with no compiler
#                    archive (default 1). For a compiler that predates the
#                    archive, such as the pinned gen0.
#   CORPUS_PER_MODULE  1 runs the per-module mode (default 0, which exports
#                    BLINK_PER_MODULE=0 for the one-unit build): every build,
#                    the row's own and each one its test starts through the
#                    CLI, takes the per-module path (BLINK_PER_MODULE=1), with
#                    no compiler archive, since a per-module build falls back
#                    to one unit under one. Writes build/corpus_per_module.json
#                    (build/corpus_per_module_subset.json under --only) and runs
#                    no lint; corpus_per_module_check.sh judges it.
#
# --only <list file> restricts the run to the files named in the list (one
# path per line, blank lines and # comments ignored) and defaults CORPUS_OUT
# to build/corpus_subset.json. The typecheck suite uses this.
#
# --per-module-slice <list file> also runs each file the list names (same
# format) as a second row on the per-module path (corpus_one.sh pm), in the
# same sweep, and writes those rows to CORPUS_PM_SLICE_OUT (default
# build/corpus_per_module_slice.json), not to CORPUS_OUT. Only in the default
# mode: the per-module mode already builds every row that way. The run does
# not judge the slice; corpus_per_module_check.sh --slice does.
#
# Rows start longest first, by the seconds each took in the last run's JSON,
# so the slowest files do not start last and hold the sweep open. A row the
# last run did not have starts first.
#
# A second summary line gives the known failures: test.failing rows that
# still fail, which a passing file hides (see corpus_one.sh), and the passing
# files whose report did not read. A third gives how many binaries linked
# the prebuilt compiler archive; corpus_check.sh holds that to a floor.
#
# Hundreds of files import the compiler modules, and each would compile the
# whole compiler into its own unit. So the run first builds those modules once
# into a compiler archive with the compiler under test, and exports
# BLINK_COMPILER_ARCHIVE so each build that imports them links it instead.
#
# The per-module mode leaves the compiler modules in each program, so a file
# that imports them builds the whole compiler in units of its own: about 3 s
# per file, against 0.6 s when it links the archive. That is the
# point of the mode, since those are the largest programs the corpus has.
#
# Exit: 2 when the run itself cannot be trusted (no compiler, malformed JSON).
# Under --only, 1 when any listed file fails: a bucket names files that must
# pass, so its exit code must say whether they did. A full run exits 0 with
# failing files, because its judge is corpus-check. A caller that holds a subset to its own floor (the suites,
# corpus-sample) accepts 1 and reads the JSON.
set -u
cd "$(dirname "$0")/.." || exit 2

only=""
run_lint=1
slice=""
while [ $# -gt 0 ]; do
    case "$1" in
        --only) only="$2"; shift 2 ;;
        --no-lint) run_lint=0; shift ;;
        --per-module-slice) slice="$2"; shift 2 ;;
        *) echo "corpus: unknown argument $1" >&2; exit 2 ;;
    esac
done

comp="${CORPUS_COMPILER:-build/gen1}"
per_module="${CORPUS_PER_MODULE:-0}"
case "$per_module" in
    0|1) ;;
    *) echo "corpus: CORPUS_PER_MODULE must be 0 or 1, got '$per_module'" >&2; exit 2 ;;
esac
jobs="${CORPUS_JOBS:-$(./scripts/default_jobs.sh)}"

# Boehm sizes its marker pool from the machine, not from this worker count, so
# every worker starts ~one marker per core and the sweep oversubscribes by that
# factor. Parallel marking also spends about twice the CPU to halve the wall
# time of one file, which is a loss when the win we want is sweep throughput.
export GC_MARKERS="${GC_MARKERS:-1}"
suffix=""
[ "$per_module" = 1 ] && suffix="_per_module"
if [ -n "$only" ]; then
    out="${CORPUS_OUT:-build/corpus${suffix}_subset.json}"
else
    out="${CORPUS_OUT:-build/corpus${suffix}.json}"
fi
slice_out="${CORPUS_PM_SLICE_OUT:-build/corpus_per_module_slice.json}"
if [ -n "$slice" ]; then
    if [ "$per_module" = 1 ]; then
        echo "corpus: --per-module-slice is for the default mode; CORPUS_PER_MODULE=1 builds every row per-module" >&2
        exit 2
    fi
    if [ ! -f "$slice" ]; then
        echo "corpus: no per-module slice list $slice" >&2
        exit 2
    fi
fi
# Each mode sets the path itself, so a caller's env cannot move the default one.
if [ "$per_module" = 1 ]; then
    export BLINK_PER_MODULE=1
    run_lint=0
    # A per-module build runs one cc per unit, up to the CPU count at once, and
    # each worker runs one build: hold the product to the core count.
    pm_jobs=$(( $(nproc 2>/dev/null || echo 8) / jobs ))
    [ "$pm_jobs" -lt 1 ] && pm_jobs=1
    export BLINK_JOBS="${BLINK_JOBS:-$pm_jobs}"
else
    # The per-module path is blink's default, so an unset env would not keep this
    # mode on one unit once the compiler archive is off.
    export BLINK_PER_MODULE=0
fi

if [ ! -x "$comp/blink" ] || [ ! -x "$comp/blinkc" ]; then
    echo "corpus: no compiler at $comp (run 'task gen1' or set CORPUS_COMPILER)" >&2
    exit 2
fi
for tool in parallel jq bc timeout nm; do
    command -v "$tool" >/dev/null 2>&1 || { echo "corpus: missing tool: $tool" >&2; exit 2; }
done

list=$(mktemp)
slice_list=$(mktemp)
rows=$(mktemp)
sweep_out=$(mktemp)
# One scratch root for the sweep: corpus_one.sh makes each row's TMPDIR inside it. A row
# that stop_running kills with SIGKILL cannot clean up, so the root is removed here, and
# it names the daemons a row starts by their working dir. The names are short: a daemon
# test puts a socket under the scratch dir, and a socket path has a length limit.
sweep_tmp=$(mktemp -d "${TMPDIR:-/tmp}/bcs-XXXXXX") || exit 2
export BLINK_CORPUS_SWEEP_TMP="$sweep_tmp"
trap 'rm -f "$list" "$slice_list" "$rows" "$sweep_out"; rm -rf "$sweep_tmp"' EXIT

# A ci step that fails beside the corpus makes task stop it with INT, then kill it
# about 2 s later; the builds and the sweep below would run on to the end with no
# one to read them. Each heavy step runs in the background, so a trapped signal
# runs the handler at once and not after the step ends. The handler stops each
# tree before it reads it again, so no process forks a child it misses; it walks
# parent links and not process groups, because timeout puts each row in a group
# of its own. Bash starts a background step with INT and QUIT ignored, and every
# process under it inherits that, so each step resets them first: a row sees the
# signals it saw when the sweep ran in the foreground.
running=()
# tree <pid>...: the pids and all their descendants, from one ps. task kills this
# script 2 s after its INT, so a ps per process is too slow for a full sweep.
tree() {
    ps -e -o pid=,ppid= | awk -v roots="$*" '
        { kids[$2] = kids[$2] " " $1 }
        END {
            n = split(roots, q, " ")
            for (i = 1; i <= n; i++) {
                print q[i]
                m = split(kids[q[i]], c, " ")
                for (j = 1; j <= m; j++) q[++n] = c[j]
            }
        }'
}
stop_running() {
    trap - TERM INT
    local seen="" now p mine=()
    # A step that ended has a pid the system may give to another process.
    for p in "${running[@]}"; do
        [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = "$$" ] && mine+=("$p")
    done
    # A daemon a row starts leaves the tree when it detaches. Each row runs in its
    # own dir under build/corpus/work, and a test's scratch tree is under the sweep root,
    # so either working dir finds it.
    mine+=($(find /proc/[0-9]*/cwd -maxdepth 0 \( -lname "$(pwd)/build/corpus/work/*" -o -lname "$sweep_tmp/*" \) 2>/dev/null \
        | awk -F/ '{ print $3 }'))
    for _ in 1 2 3 4 5; do
        now=$(tree "${mine[@]}")
        [ -n "$now" ] || break
        kill -STOP $now 2>/dev/null
        [ "$now" = "$seen" ] && break
        seen=$now
    done
    [ -n "$seen" ] && kill -KILL $seen 2>/dev/null
    rm -rf "$sweep_tmp"
    echo "corpus: stopped by signal, $(echo $seen | wc -w) process(es) killed" >&2
    exit "$1"
}
trap 'stop_running 130' INT
trap 'stop_running 143' TERM
if [ -n "$only" ]; then
    # The sandbox and the result record are keyed on the basename, so a
    # file listed twice would run twice in the same directory.
    grep -vE '^[[:space:]]*(#|$)' "$only" | awk '!seen[$0]++' > "$list"
else
    ls tests/test_*.bl | LC_ALL=C sort > "$list"
fi
total=$(wc -l < "$list" | tr -d ' ')
if [ "$total" -eq 0 ]; then
    echo "corpus: no test files selected" >&2
    exit 2
fi
if [ -n "$slice" ]; then
    ./scripts/corpus_per_module_slice_entries.sh "$slice" > "$slice_list"
fi
slice_total=$(wc -l < "$slice_list" | tr -d ' ')

# One job per line: a file, then its rows' modes (- for the sweep's own mode,
# pm for a per-module slice row). A file's rows run one after the other in one
# job: corpus_one.sh holds a lock per file, so two jobs of one file would leave
# a worker idle on the lock. The longest jobs start first, by the previous
# seconds from the JSON this run is about to replace; a job with a row new to
# that JSON starts before all others.
{
    for j in "$out" "$slice_out"; do
        m=""
        [ "$j" = "$slice_out" ] && m=pm
        [ "$j" = "$slice_out" ] && [ -z "$slice" ] && continue
        jq -r --arg m "$m" '.files[]? | "\(.file)\t\($m)\t\(.seconds)"' "$j" 2>/dev/null
    done
    awk '{ print $0 "\t\t-" }' "$list"
    awk '{ print $0 "\tpm\t-" }' "$slice_list"
} | awk -F'\t' '
    $3 != "-" { secs[$1 FS $2] = $3; next }
    !($1 in total) { order[++n] = $1 }
    {
        k = $1 FS $2
        total[$1] += (k in secs ? secs[k] : 1e9)
        modes[$1] = modes[$1] " " ($2 == "" ? "-" : $2)
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s%s\n", total[order[i]], order[i], modes[order[i]] }' \
  | LC_ALL=C sort -t"$(printf '\t')" -k1,1gr -k2,2 | cut -f2- > "$rows"

[ -f build/gc_unity.c ] || ./scripts/gen_gc_unity.sh build/gc_unity.c || exit 2

results="build/corpus/results"
rm -rf "$results" build/corpus/work build/corpus/native build/corpus/compiler_archive build/corpus/cc build/corpus/pch build/corpus/locks
mkdir -p "$results" build/corpus

# The corpus builds with --debug for debug_assert and the runtime's debug
# checks. The -g that --debug also passes changes no code, nothing in the
# corpus reads debug info, and it costs cc and link time in every build. The
# compiler archive and each file's build run with this cc first on PATH, which
# drops -g and runs the real cc. It also passes -Winvalid-pch, so a row whose
# cc drops the PCH below says why in its log.
real_cc="$(command -v cc)" || { echo "corpus: no cc on PATH" >&2; exit 2; }
mkdir -p build/corpus/cc
printf '#!/bin/sh\nfor a do\n    shift\n    [ "$a" = -g ] || set -- "$@" "$a"\ndone\nexec %s -Winvalid-pch "$@"\n' "'$real_cc'" > build/corpus/cc/cc
chmod +x build/corpus/cc/cc

# A file whose program links a vendored native dep compiles that dep's C source
# into its sandbox `.tmp`, and each sandbox starts empty, so the sweep compiled
# sqlite3 once per such file. Build each object once with the flags a corpus
# build uses (those of `blink build --debug`, less -g); corpus_one.sh copies it
# in with its mtime, which is what lets the build skip the compile.
#
# The native objects, the PCH and the compiler archive read nothing the others
# write, and each is one cc on one core, so they build at once.
mkdir -p build/corpus/native
native_pids=()
for d in lib/native/*/; do
    name=$(basename "$d")
    [ -f "$d$name.c" ] || continue
    (trap - INT QUIT; exec cc -pipe -O0 -c -o "build/corpus/native/$name.o" "$d$name.c") &
    native_pids+=("$!")
    running+=("$!")
done

# Each row's unit includes libblink_std.h first, and reading it is about a
# quarter of a small row's cc. Precompile it once, beside links to the two
# headers a sandbox links, with the flags of a corpus build: those of
# `blink build --debug`, less -g, plus the define the unit puts before the
# include (-pthread defines _REENTRANT, which the header reads). gcc drops a
# PCH built with other flags or macros and reads the header instead. With no
# PCH every row still builds, so a failure here costs time only.
pch_key=$(./scripts/corpus_std_pch_key.sh "$comp")
pch_pid=""
if [ -n "$pch_key" ]; then
    pch_dir="build/corpus/pch/$(sed -n 1p <<< "$pch_key")"
    mkdir -p "$pch_dir"
    ln -s "$(sed -n 2p <<< "$pch_key")" "$pch_dir/libblink_std.h"
    ln -s "$(sed -n 3p <<< "$pch_key")" "$pch_dir/runtime.h"
    (
        trap - INT QUIT
        if ! cc -pipe -O0 -DBLINK_DEBUG -pthread -DBLINK_USE_EXTERN_RUNTIME_STORAGE=1 -x c-header \
                -o "$pch_dir/libblink_std.h.gch.tmp" "$pch_dir/libblink_std.h" > build/corpus/pch.log 2>&1 \
                || ! mv "$pch_dir/libblink_std.h.gch.tmp" "$pch_dir/libblink_std.h.gch"; then
            echo "corpus: no PCH of libblink_std.h, rows read the header (see build/corpus/pch.log)" >&2
        fi
    ) &
    pch_pid=$!
    running+=("$pch_pid")
fi

# The roots are the modules the compiler binary imports plus the test helpers
# that import the codegen; the archive holds their import closure. The helper
# every runtime test imports, compile_test_helpers, stays out: it imports no
# compiler module, and a file that links the archive pays to read its header.
# No fallback when this fails: a run that quietly built each file in one unit
# would report the old cost as if it were the new.
carchive="$(pwd)/build/corpus/compiler_archive"
if [ "${CORPUS_COMPILER_ARCHIVE:-1}" = 0 ] || [ "$per_module" = 1 ]; then
    unset BLINK_COMPILER_ARCHIVE
else
    roots=$(sed -n 's/^import \([a-z_][a-z_0-9]*\).*/\1/p' src/blinkc_main.bl | grep -vx std | sort -u)
    (trap - INT QUIT; unset BLINK_ROOT BLINK_COMPILER_ARCHIVE; PATH="$(pwd)/build/corpus/cc:$PATH" \
        exec "$comp/blink" __build-compiler-archive "$carchive" \
        $roots cg_test_helpers lower_test_helpers cname_test_helpers) > build/corpus/compiler_archive.log 2>&1 &
    archive_pid=$!
    running+=("$archive_pid")
    wait "$archive_pid"
    archive_rc=$?
    if [ "$archive_rc" -ne 0 ] || [ ! -f "$carchive/libblink_compiler.a" ]; then
        echo "corpus: ERROR the compiler archive did not build, see build/corpus/compiler_archive.log" >&2
        tail -20 build/corpus/compiler_archive.log >&2
        exit 2
    fi
    export BLINK_COMPILER_ARCHIVE="$carchive"
fi

for p in "${native_pids[@]}"; do
    wait "$p" || exit 2
done
[ -n "$pch_pid" ] && wait "$pch_pid"

# Instructions and CPU time cover the per-file compile and run only (the
# parallel sweep and the processes it starts), not the gen1 build, the compiler
# archive or the PCH before it. Wall time moves with machine load; user-space
# instructions do not. The measurement is optional: a perf that is missing or
# denied (a probe run decides) leaves the sweep unwrapped and the fields null.
perf_out="build/corpus/perf_stat.txt"
rm -f "$perf_out"
perf_cmd=()
perf_bin="${PERF:-perf}"
if command -v "$perf_bin" >/dev/null 2>&1 \
        && "$perf_bin" stat -x, -e instructions:u,task-clock -o /dev/null -- true >/dev/null 2>&1; then
    perf_cmd=("$perf_bin" stat -x, -e instructions:u,task-clock -o "$perf_out" --)
fi

# The same share of the CPUs a per-module run gives each worker.
pm_row_jobs=$(( $(nproc 2>/dev/null || echo 8) / jobs ))
[ "$pm_row_jobs" -lt 1 ] && pm_row_jobs=1
export CORPUS_PM_BLINK_JOBS="$pm_row_jobs"

mode_note=""
[ "$per_module" = 1 ] && mode_note=", per-module, BLINK_JOBS=$BLINK_JOBS"
[ "$slice_total" -gt 0 ] && mode_note="$mode_note, $slice_total per-module slice rows at BLINK_JOBS=$pm_row_jobs"
echo "corpus: $total files, compiler $comp, $jobs workers$mode_note"
run_rows() {
    f=$1
    shift
    for m in "$@"; do
        [ -n "$m" ] || continue
        ./scripts/corpus_one.sh "$f" "$CORPUS_COMP" "$CORPUS_RESULTS" "${m#-}"
    done
}
export -f run_rows
export CORPUS_COMP="$comp" CORPUS_RESULTS="$results"
start=$(date +%s)
(trap - INT QUIT; exec "${perf_cmd[@]}" env PARALLEL_SHELL=bash parallel -j "$jobs" --halt never \
    --line-buffer --colsep ' ' run_rows {1} {2} {3} :::: "$rows") > "$sweep_out" &
sweep_pid=$!
running=("$sweep_pid")
wait "$sweep_pid"
awk '{ n[$1]++ } END { for (k in n) printf "corpus: %s %d\n", k, n[k] }' "$sweep_out"
end=$(date +%s)

# Each field reads null unless perf wrote a plain number for it; a counter
# perf could not read prints "<not counted>" and must not become a value.
instructions_u=null
cpu_seconds=null
if [ -s "$perf_out" ]; then
    i=$(awk -F, '$3 ~ /^instructions/ && $1 ~ /^[0-9]+$/ { print $1; exit }' "$perf_out")
    ms=$(awk -F, '$3 ~ /^task-clock/ && $1 ~ /^[0-9]+(\.[0-9]+)?$/ { print $1; exit }' "$perf_out")
    [ -n "$i" ] && instructions_u="$i"
    [ -n "$ms" ] && cpu_seconds=$(awk -v ms="$ms" 'BEGIN { printf "%.2f", ms / 1000 }')
fi

# One record per file, in list order; a file with no record means the
# runner itself died, which is recorded as compile_fail so the total holds.
# records <list> <record suffix>
records() {
    awk -v r="$results" -v sfx="$2" '{
        b = $0; sub(/.*\//, "", b); sub(/\.bl$/, "", b)
        p = r "/" b sfx ".json"
        if ((getline line < p) > 0) { print line; close(p) }
        else printf "{\"file\":\"%s\",\"status\":\"compile_fail\",\"seconds\":0,\"first_error_line\":\"corpus runner produced no record\",\"known_failures\":null,\"compiler_archive\":false,\"per_module\":false}\n", $0
    }' "$1"
}

comp_sha=$(sha256sum "$(readlink -f "$comp/blinkc")" | cut -c1-16)
# write_json <records> <out> <per_module>. The CPU time and instructions cover
# the whole sweep, slice rows too, so they go in the main JSON only.
write_json() {
    local cpu=null ins=null
    if [ "$2" = "$out" ]; then cpu="$cpu_seconds"; ins="$instructions_u"; fi
    jq -s \
    --arg compiler "$comp" \
    --arg blinkc_sha256_prefix "$comp_sha" \
    --arg git "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson secs "$((end - start))" \
    --argjson instructions_u "$ins" \
    --argjson cpu_seconds "$cpu" \
    --argjson slice_rows "$slice_total" \
    --argjson per_module "$3" '
    {
      compiler: $compiler,
      blinkc_sha256_prefix: $blinkc_sha256_prefix,
      git_head: $git,
      generated_utc: $when,
      per_module: $per_module,
      wall_seconds: $secs,
      cpu_seconds: $cpu_seconds,
      instructions_u: $instructions_u,
      total: length,
      passed: (map(select(.status == "pass")) | length),
      compile_fail: (map(select(.status == "compile_fail")) | length),
      run_fail: (map(select(.status == "run_fail")) | length),
      timeout: (map(select(.status == "timeout")) | length),
      known_failures: (map(.known_failures // 0) | add // 0),
      compiler_archive_linked: (map(select(.compiler_archive == true)) | length),
      per_module_built: (map(select(.per_module == true)) | length),
      per_module_slice_rows_in_sweep: $slice_rows,
      files: .
    }' "$1" > "$2"
}

# A truncated or malformed result file must fail here, not read as 0/0 later.
check_json() {
    if ! jq -e '(.total|type=="number") and (.passed|type=="number") and (.files|type=="array") and (.total == (.files|length))' "$1" >/dev/null 2>&1; then
        echo "corpus: ERROR $1 is malformed" >&2
        exit 2
    fi
}

records "$list" "" > "$rows"
write_json "$rows" "$out" "$([ "$per_module" = 1 ] && echo true || echo false)"
check_json "$out"
if [ -n "$slice" ]; then
    records "$slice_list" .pm > "$rows"
    write_json "$rows" "$slice_out" true
    check_json "$slice_out"
fi
passed=$(jq -r .passed "$out")
if [ "$instructions_u" != null ] && [ "$cpu_seconds" != null ]; then
    perf_note=$(awk -v c="$cpu_seconds" -v i="$instructions_u" 'BEGIN { printf "cpu %ss, %.2f G instructions", c, i / 1e9 }')
else
    perf_note="perf n/a"
fi
echo "corpus: $passed/$total passed in $((end - start))s ($perf_note) -> $out"
if [ "$passed" -ne "$total" ]; then
    echo "corpus: failing files:"
    jq -r '.files[] | select(.status != "pass") | "  \(.status) \(.file): \(.first_error_line)"' "$out"
fi
jq -r '
    (.files | map(select((.known_failures // 0) > 0))) as $counted
    | (.files | map(select(.status == "pass" and .known_failures == null))) as $unread
    | "corpus: known failures \(.known_failures) in \($counted | length) file(s), \($unread | length) unreadable report(s)",
      ($counted[] | "  \(.known_failures) \(.file)"),
      ($unread[] | "  unreadable \(.file)")' "$out"

echo "compiler-archive: linked $(jq -r .compiler_archive_linked "$out") files"
[ "$per_module" = 1 ] && echo "per-module: built $(jq -r .per_module_built "$out") files in units"
if [ -n "$slice" ]; then
    echo "per-module slice: $(jq -r '"\(.passed)/\(.total) passed, \(.per_module_built) built in units"' "$slice_out") -> $slice_out"
    jq -r '.files[] | select(.status != "pass") | "  \(.status) \(.file): \(.first_error_line)"' "$slice_out"
fi

if [ "$run_lint" -eq 1 ] && [ -z "$only" ]; then
    ./scripts/lint_codegen.sh || exit 1
fi
if [ -n "$only" ] && [ "$passed" -ne "$total" ]; then
    exit 1
fi
exit 0
