#!/bin/bash
# Compile and run every tests/test_*.bl independently and write
# build/corpus.json. This is the progress metric for the codegen rewrite: a
# pass count over the whole corpus, with no fail-fast and no directory-mode
# pre-typecheck, so a tree that compiles only part of the corpus still gets
# an honest number.
#
# The compiler under test is gen1 — the CURRENT source compiled by the pinned
# gen0. gen0 itself is a fixed binary, so a corpus run against it measures
# nothing about the tree and never moves.
#
#   scripts/corpus.sh [--only <list file>] [--no-lint]
#
# Env:
#   CORPUS_COMPILER  dir holding blink/blinkc/libblink_std.* (default build/gen1)
#   CORPUS_JOBS      parallel workers (default: nproc/2, minimum 1)
#   CORPUS_OUT       output JSON (default build/corpus.json)
#   CORPUS_PRELUDE_LIB  lib/ root each sandbox exposes as the prelude, passed
#                    through to corpus_one.sh (default: the compiler's own)
#
# --only <list file> restricts the run to the files named in the list (one
# path per line, blank lines and # comments ignored) and defaults CORPUS_OUT
# to build/corpus_subset.json. The typecheck suite uses this.
set -u
cd "$(dirname "$0")/.." || exit 2

only=""
run_lint=1
while [ $# -gt 0 ]; do
    case "$1" in
        --only) only="$2"; shift 2 ;;
        --no-lint) run_lint=0; shift ;;
        *) echo "corpus: unknown argument $1" >&2; exit 2 ;;
    esac
done

comp="${CORPUS_COMPILER:-build/gen1}"
# Half the cores by default: the sweep forks timeout -> blink -> cc per file,
# so a full-width run saturates the machine and starves everything else.
default_jobs=$(( $(nproc 2>/dev/null || echo 8) / 2 ))
[ "$default_jobs" -lt 1 ] && default_jobs=1
jobs="${CORPUS_JOBS:-$default_jobs}"

# Boehm sizes its marker pool from the machine, not from this worker count, so
# every worker starts ~one marker per core and the sweep oversubscribes by that
# factor. Parallel marking also spends about twice the CPU to halve the wall
# time of one file, which is a loss when the win we want is sweep throughput.
export GC_MARKERS="${GC_MARKERS:-1}"
if [ -n "$only" ]; then
    out="${CORPUS_OUT:-build/corpus_subset.json}"
else
    out="${CORPUS_OUT:-build/corpus.json}"
fi

if [ ! -x "$comp/blink" ] || [ ! -x "$comp/blinkc" ]; then
    echo "corpus: no compiler at $comp (run 'task gen1' or set CORPUS_COMPILER)" >&2
    exit 2
fi
for tool in parallel jq bc timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "corpus: missing tool: $tool" >&2; exit 2; }
done

list=$(mktemp)
trap 'rm -f "$list"' EXIT
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

[ -f build/gc_unity.c ] || ./scripts/gen_gc_unity.sh build/gc_unity.c || exit 2

results="build/corpus/results"
rm -rf "$results" build/corpus/work
mkdir -p "$results" build/corpus

echo "corpus: $total files, compiler $comp, $jobs workers"
start=$(date +%s)
parallel -j "$jobs" --halt never --line-buffer \
    ./scripts/corpus_one.sh {} "$comp" "$results" :::: "$list" \
    | awk '{ n[$1]++ } END { for (k in n) printf "corpus: %s %d\n", k, n[k] }'
end=$(date +%s)

# One record per file, in corpus order; a file with no record means the
# runner itself died, which is recorded as compile_fail so the total holds.
records=$(mktemp)
while IFS= read -r f; do
    b=$(basename "$f" .bl)
    if [ -f "$results/$b.json" ]; then
        cat "$results/$b.json"
    else
        printf '{"file":"%s","status":"compile_fail","seconds":0,"first_error_line":"corpus runner produced no record"}\n' "$f"
    fi
done < "$list" > "$records"

comp_sha=$(sha256sum "$(readlink -f "$comp/blinkc")" | cut -c1-16)
jq -s \
    --arg compiler "$comp" \
    --arg blinkc_sha256_prefix "$comp_sha" \
    --arg git "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson secs "$((end - start))" '
    {
      compiler: $compiler,
      blinkc_sha256_prefix: $blinkc_sha256_prefix,
      git_head: $git,
      generated_utc: $when,
      wall_seconds: $secs,
      total: length,
      passed: (map(select(.status == "pass")) | length),
      compile_fail: (map(select(.status == "compile_fail")) | length),
      run_fail: (map(select(.status == "run_fail")) | length),
      timeout: (map(select(.status == "timeout")) | length),
      files: .
    }' "$records" > "$out"
rm -f "$records"

# A truncated or malformed result file must fail here, not read as 0/0 later.
if ! jq -e '(.total|type=="number") and (.passed|type=="number") and (.files|type=="array") and (.total == (.files|length))' "$out" >/dev/null 2>&1; then
    echo "corpus: ERROR $out is malformed" >&2
    exit 2
fi
passed=$(jq -r .passed "$out")
echo "corpus: $passed/$total passed in $((end - start))s -> $out"
if [ "$passed" -ne "$total" ]; then
    echo "corpus: failing files:"
    jq -r '.files[] | select(.status != "pass") | "  \(.status) \(.file): \(.first_error_line)"' "$out"
fi

if [ "$run_lint" -eq 1 ] && [ -z "$only" ]; then
    ./scripts/lint_codegen.sh || exit 1
fi
exit 0
