#!/bin/bash
# Compile and run every tests/test_*.bl independently and write
# build/corpus.json, with no fail-fast and no directory-mode pre-typecheck, so
# one broken file cannot hide the result of the others.
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
#   CORPUS_COMPILER_ARCHIVE  0 builds every file in one unit, with no compiler
#                    archive (default 1). For a compiler that predates the
#                    archive, such as the pinned gen0 the suites run under.
#
# --only <list file> restricts the run to the files named in the list (one
# path per line, blank lines and # comments ignored) and defaults CORPUS_OUT
# to build/corpus_subset.json. The typecheck suite uses this.
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
# Exit: 2 when the run itself cannot be trusted (no compiler, malformed JSON).
# Under --only, 1 when any listed file fails: a bucket names files that must
# pass, so its exit code must say whether they did. A full run exits 0 with
# failing files, because its judge is corpus-check. A caller that holds a subset to its own floor (the suites,
# corpus-sample) accepts 1 and reads the JSON.
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
for tool in parallel jq bc timeout nm; do
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
rm -rf "$results" build/corpus/work build/corpus/native build/corpus/compiler_archive build/corpus/cc build/corpus/pch
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
# into its sandbox .tmp/, and each sandbox starts empty, so the sweep compiled
# sqlite3 once per such file. Build each object once with the flags a corpus
# build uses (those of `blink build --debug`, less -g); corpus_one.sh copies it
# in with its mtime, which is what lets the build skip the compile.
mkdir -p build/corpus/native
for d in lib/native/*/; do
    name=$(basename "$d")
    [ -f "$d$name.c" ] || continue
    cc -pipe -O0 -c -o "build/corpus/native/$name.o" "$d$name.c" || exit 2
done

# Each row's unit includes libblink_std.h first, and reading it is about a
# quarter of a small row's cc. Precompile it once, beside links to the two
# headers a sandbox links, with the flags of a corpus build: those of
# `blink build --debug`, less -g, plus the define the unit puts before the
# include (-pthread defines _REENTRANT, which the header reads). gcc drops a
# PCH built with other flags or macros and reads the header instead. With no
# PCH every row still builds, so a failure here costs time only.
pch_key=$(./scripts/corpus_std_pch_key.sh "$comp")
if [ -n "$pch_key" ]; then
    pch_dir="build/corpus/pch/$(sed -n 1p <<< "$pch_key")"
    mkdir -p "$pch_dir"
    ln -s "$(sed -n 2p <<< "$pch_key")" "$pch_dir/libblink_std.h"
    ln -s "$(sed -n 3p <<< "$pch_key")" "$pch_dir/runtime.h"
    if ! cc -pipe -O0 -DBLINK_DEBUG -pthread -DBLINK_USE_EXTERN_RUNTIME_STORAGE=1 -x c-header \
            -o "$pch_dir/libblink_std.h.gch.tmp" "$pch_dir/libblink_std.h" > build/corpus/pch.log 2>&1 \
            || ! mv "$pch_dir/libblink_std.h.gch.tmp" "$pch_dir/libblink_std.h.gch"; then
        echo "corpus: no PCH of libblink_std.h, rows read the header (see build/corpus/pch.log)" >&2
    fi
fi

# The roots are the modules the compiler binary imports; the archive holds their
# import closure. The test helpers stay out, those that import the codegen too:
# an assert jumps back to the test runner through state each unit keeps for
# itself, so an assert compiled into the archive jumps through a runner that
# never ran and crashes the test. A test still links the archive for the
# compiler modules its helpers import.
# No fallback when this fails: a run that quietly built each file in one unit
# would report the old cost as if it were the new.
carchive="$(pwd)/build/corpus/compiler_archive"
if [ "${CORPUS_COMPILER_ARCHIVE:-1}" = 0 ]; then
    unset BLINK_COMPILER_ARCHIVE
else
    roots=$(sed -n 's/^import \([a-z_][a-z_0-9]*\).*/\1/p' src/blinkc_main.bl | grep -vx std | sort -u)
    if ! (unset BLINK_ROOT BLINK_COMPILER_ARCHIVE; PATH="$(pwd)/build/corpus/cc:$PATH" \
            "$comp/blink" __build-compiler-archive "$carchive" \
            $roots) > build/corpus/compiler_archive.log 2>&1 \
            || [ ! -f "$carchive/libblink_compiler.a" ]; then
        echo "corpus: ERROR the compiler archive did not build, see build/corpus/compiler_archive.log" >&2
        tail -20 build/corpus/compiler_archive.log >&2
        exit 2
    fi
    export BLINK_COMPILER_ARCHIVE="$carchive"
fi

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
        printf '{"file":"%s","status":"compile_fail","seconds":0,"first_error_line":"corpus runner produced no record","known_failures":null,"compiler_archive":false}\n' "$f"
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
      known_failures: (map(.known_failures // 0) | add // 0),
      compiler_archive_linked: (map(select(.compiler_archive == true)) | length),
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
jq -r '
    (.files | map(select((.known_failures // 0) > 0))) as $counted
    | (.files | map(select(.status == "pass" and .known_failures == null))) as $unread
    | "corpus: known failures \(.known_failures) in \($counted | length) file(s), \($unread | length) unreadable report(s)",
      ($counted[] | "  \(.known_failures) \(.file)"),
      ($unread[] | "  unreadable \(.file)")' "$out"

echo "compiler-archive: linked $(jq -r .compiler_archive_linked "$out") files"

if [ "$run_lint" -eq 1 ] && [ -z "$only" ]; then
    ./scripts/lint_codegen.sh || exit 1
fi
if [ -n "$only" ] && [ "$passed" -ne "$total" ]; then
    exit 1
fi
exit 0
