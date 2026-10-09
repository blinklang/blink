#!/bin/bash
# Time the edit-and-rebuild loop a user sees: edit one file, then `blink build`,
# `blink run` or `blink test`. Every number on the per-module-build project comes
# from this script, so later changes compare against the same edits and cases.
#
#   scripts/bench_edit_loop.sh [blink binary]      (default build/gen1/bin/blink)
#
# Env:
#   BENCH_REPS=5           runs per case (the row gives median, min, max)
#   BENCH_OUT=<file>       TSV out (default build/bench_edit_loop.tsv); per-run rows and
#                          C hashes go to <file>.runs
#   BENCH_TARGETS="cli small"  targets to run
#   BENCH_CASES="..."      only these case names (default: all), e.g. "body-cname nochange"
#   BENCH_LOAD=3           wait for the 1-min load average to drop below this before each run
#   BENCH_WAIT_CAP=1800    seconds to wait for load before giving up (outer) or going on (per run)
#   BENCH_SLICE=blink-gates.slice  systemd user slice to run in; empty runs in place
#   BENCH_WORKDIR=<dir>    parent of the scratch tree (default ${TMPDIR:-/tmp})
#   BENCH_KEEP=1           keep the scratch tree
#   BENCH_FLAGS="..."      extra flags for the build, run and test cases, e.g.
#                          "--no-per-module" for the one-unit build. A per-module build (the
#                          default) has its C hash cover the units dir (<stem>.units/*.c and
#                          *.h); a one-unit build hashes <stem>.c
#   BENCH_DAEMON=1         start `blink daemon start <target src>` in the target dir once it is
#                          warm, so the build and run cases build through the daemon; it stops
#                          when the target is done. A header line gives the builds it served
#   BENCH_SETTLE=<s>       seconds to wait between the edit and the timed run (default 0). A
#                          user takes some time between saving and building; with the daemon,
#                          its recheck after the edit runs then
#
# Setup. The tree (tracked + untracked, not ignored) is copied to a scratch dir, so the
# real src/ is never edited. The binary is copied to <scratch>/build/blink: that is the
# dev layout of a seeded build/, so the std archive is a dev archive under
# <scratch>/build/std-cache that a cold case can clear and rebuild.
#
# Targets:
#   cli    src/cli.bl, built from the scratch root (the compiler)
#   small  bench/edit_loop/src/main.bl, built from bench/edit_loop (6 modules, std.json)
#
# Cases (each row says the file it edits):
#   nochange             (c) rebuild with no edit
#   body-<module>        (a) private-body edit: one line added to a private fn
#   pubfn-<module>       (b) a new pub fn added at the end of a module
#   run-body-<module>    `blink run` after the (a) edit
#   test-body-<module>   `blink test <one test file>` after the (a) edit (debug build)
#   cold-obj             (d) obj cache cleared; std archive kept
#   cold-all             (d) obj cache and std archive cache both cleared. cli only: with
#                        no archive at the binary's root, blink looks for the archive and
#                        runtime.h in ./build, which a project dir does not have
# Each edited run writes a fresh nonce into the file, so its C differs from the warm C
# and from every other run (checked by hash; the row fails if not), and the file is
# put back after the run. So no run can hit an object another run stored.
#
# Split. A `cc` wrapper first on PATH logs each cc call. cc_s is the time at least one
# `cc -c` call ran (the units, which run in parallel, so their overlap counts once, and the
# std monolith in cold-all; with --no-per-module the user unit), link_s sums the other calls but
# `cc --version`, and emit_s = wall - cc_s - link_s: front end, codegen, cache hashing
# and process start. Each split column is its own median, so they need not add up to
# median_s. The wrapper costs a few ms per call. No trace in blink gives this split.
set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
reps=${BENCH_REPS:-5}
load_limit=${BENCH_LOAD:-3}
wait_cap=${BENCH_WAIT_CAP:-1800}
slice=${BENCH_SLICE-blink-gates.slice}

die() { echo "bench_edit_loop: $*" >&2; exit 1; }

blink_arg=${1:-build/gen1/bin/blink}
case "$blink_arg" in
    /*) blink_bin=$blink_arg ;;
    *) blink_bin=$PWD/$blink_arg ;;
esac
[ -x "$blink_bin" ] || die "no blink binary at $blink_bin"
out=${BENCH_OUT:-$repo/build/bench_edit_loop.tsv}
case "$out" in /*) ;; *) out=$PWD/$out ;; esac

load1() { cut -d' ' -f1 /proc/loadavg; }
load_below() { awk -v l="$(load1)" -v m="$1" 'BEGIN { exit !(l < m) }'; }
slice_busy() { [ "$(systemd-cgls --user-unit "$slice" --no-pager 2>/dev/null | wc -l)" -gt 1 ]; }

# Outer pass: wait for an idle machine and an empty slice, then rerun inside the slice,
# so no gate or other benchmark shares the cores with the timed runs.
if [ -n "$slice" ] && [ -z "${BENCH_IN_SLICE:-}" ]; then
    command -v systemd-run >/dev/null || die "systemd-run not found; set BENCH_SLICE= to run in place"
    t=0
    until load_below "$load_limit" && ! slice_busy; do
        [ "$t" -ge "$wait_cap" ] && die "load $(load1) or $slice busy after ${t}s"
        sleep 15; t=$((t + 15))
    done
    exec systemd-run --user --scope --slice="$slice" -q \
        env BENCH_IN_SLICE=1 bash "$0" "$blink_bin"
fi

work=$(mktemp -d "${BENCH_WORKDIR:-${TMPDIR:-/tmp}}/bench-edit-loop.XXXXXX") || die "mktemp failed"
daemon_pid=
cleanup() {
    stop_daemon
    [ "${BENCH_KEEP:-}" = 1 ] || rm -rf "$work"
}
trap cleanup EXIT

echo "bench_edit_loop: scratch tree $work"
(cd "$repo" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$work" \
    || die "copying the tree failed"
mkdir -p "$work/build" "$work/.bench/bin" "$work/.bench/logs" "$work/.bench/orig"
cp "$blink_bin" "$work/build/blink"
"$work/scripts/flatten_runtime.sh" "$work/build/runtime.h" || die "flatten_runtime failed"
"$work/scripts/gen_gc_unity.sh" "$work/build/gc_unity.c" >/dev/null || die "gen_gc_unity failed"
blink=$work/build/blink
# Built from the root so it lands in <scratch>/build; a first build from a project dir
# would look for it in that dir.
(cd "$work" && "$blink" __build-stdlib-archive) > "$work/.bench/logs/archive.log" 2>&1 \
    || die "std archive build failed (log $work/.bench/logs/archive.log)"

real_cc=$(command -v cc) || die "no cc on PATH"
cat > "$work/.bench/bin/cc" <<EOF
#!/bin/bash
t0=\$EPOCHREALTIME
"$real_cc" "\$@"
rc=\$?
t1=\$EPOCHREALTIME
kind=link
for a in "\$@"; do
    case "\$a" in
        -c) kind=cc ;;
        --version) kind=id; break ;;
    esac
done
echo "\$kind \$t0 \$t1" >> "\${BENCH_CC_LOG:-/dev/null}"
exit \$rc
EOF
chmod +x "$work/.bench/bin/cc"
export PATH="$work/.bench/bin:$PATH"

# Target table: tgt_<field>_<target>. warm() checks each file and fn, so a rename fails loudly.
tgt_dir_cli=.;                 tgt_src_cli=src/cli.bl;  tgt_test_cli=tests/test_cname_mono_types.bl
tgt_body_cli="src/cname.bl:strip_blink src/typecheck.bl:tc_variant_enum_decl_node"
tgt_pub_cli=src/cname.bl
tgt_coldall_cli=1
# The compiler tests compile probes in process, and the probe finds lib/std through
# BLINK_ROOT, as under task ci. It names the same root blink finds from its own path.
tgt_env_cli=BLINK_ROOT=$work
tgt_dir_small=bench/edit_loop; tgt_src_small=src/main.bl; tgt_test_small=src/inventory_test.bl
tgt_body_small="src/inventory.bl:restock_amount"
tgt_pub_small=src/model.bl

tv() { local v="tgt_$1_$2"; echo "${!v-}"; }
modname() { basename "$1" .bl; }
stem() { basename "$1" .bl; }

raw=$out.runs
mkdir -p "$(dirname "$out")"
: > "$raw"
printf 'target\tcase\trep\twall_s\temit_s\tcc_s\tlink_s\tcc_calls\tc_sha256\tload1\n' >> "$raw"

wait_load() {
    local t=0
    until load_below "$load_limit"; do
        [ "$t" -ge "$wait_cap" ] && { echo "bench_edit_loop: load $(load1) after ${t}s, running anyway" >&2; return; }
        sleep 5; t=$((t + 5))
    done
}

case_wanted() {
    [ -z "${BENCH_CASES:-}" ] && return 0
    case " $BENCH_CASES " in *" $1 "*) return 0 ;; esac
    return 1
}

# run_blink <target> <log> <args...>: runs blink in the target dir, sets $wall, $rc.
run_blink() {
    local target=$1 log=$2; shift 2
    local dir=$work/$(tv dir "$target") t0 t1
    : > "$work/.bench/cc.log"
    t0=$EPOCHREALTIME
    (cd "$dir" && env BENCH_CC_LOG="$work/.bench/cc.log" $(tv env "$target") "$blink" "$@") > "$log" 2>&1
    rc=$?
    t1=$EPOCHREALTIME
    wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')
}

restore() { cp "$work/.bench/orig/$2" "$work/$(tv dir "$1")/$3"; }

# start_daemon <target>: the daemon runs under the env run_blink gives blink, since it builds
# only for a client whose env is its own.
start_daemon() {
    local target=$1 dir=$work/$(tv dir "$1") i
    (cd "$dir" && exec env BENCH_CC_LOG="$work/.bench/cc.log" $(tv env "$target") "$blink" daemon start "$(tv src "$target")") \
        > "$work/.bench/logs/$target-daemon.log" 2>&1 &
    daemon_pid=$!
    for i in $(seq 1 600); do
        (cd "$dir" && "$blink" daemon status) > /dev/null 2>&1 && return 0
        kill -0 "$daemon_pid" 2>/dev/null || break
        sleep 0.05
    done
    stop_daemon
    die "$target: the daemon did not start (log $work/.bench/logs/$target-daemon.log)"
}

stop_daemon() {
    [ -n "$daemon_pid" ] || return 0
    kill "$daemon_pid" 2>/dev/null
    local i
    for i in $(seq 1 100); do
        kill -0 "$daemon_pid" 2>/dev/null || break
        sleep 0.05
    done
    kill -9 "$daemon_pid" 2>/dev/null
    daemon_pid=
}

# daemon_builds <target>: how many builds the daemon ran, from `blink daemon status`.
daemon_builds() {
    (cd "$work/$(tv dir "$1")" && "$blink" daemon status 2>/dev/null) | sed -n 's/.*"builds":\([0-9]*\).*/\1/p'
}

edit_body() {
    local f=$1 fn=$2 nonce=$3
    sed -i "/^fn $fn(/a\\    let _bench_edit = \"$nonce\"" "$f"
}
edit_pub() { printf '\npub fn bench_added_%s() -> Int { 1 }\n' "$2" >> "$1"; }

# rep <target> <case> <rep> <c file> <kind> [file fn]: one timed run, appended to $raw.
rep() {
    local target=$1 cs=$2 r=$3 cfile=$4 kind=$5 efile=${6:-} efn=${7:-}
    local dir=$work/$(tv dir "$target") nonce="b$(date +%s%N)r$r" args
    local log=$work/.bench/logs/$target-$cs-$r.log
    wait_load
    case "$kind" in
        body|run|test) edit_body "$dir/$efile" "$efn" "$nonce" ;;
        pub) edit_pub "$dir/$efile" "$nonce" ;;
        cold-obj) rm -rf "$dir/build/obj-cache" ;;
        cold-all)
            rm -rf "$dir/build/obj-cache"
            (cd "$work/build" && rm -rf std-cache libblink_std.a libblink_std.h skip_modules.txt .archive-id) ;;
    esac
    case "$kind" in
        run) args=(run "$(tv src "$target")" ${BENCH_FLAGS:-}) ;;
        test) args=(test "$(tv test "$target")" ${BENCH_FLAGS:-}) ;;
        *) args=(build "$(tv src "$target")" ${BENCH_FLAGS:-}) ;;
    esac
    [ "${BENCH_SETTLE:-0}" = 0 ] || sleep "$BENCH_SETTLE"
    local load=$(load1)
    run_blink "$target" "$log" "${args[@]}"
    [ -n "$efile" ] && restore "$target" "$target-$(stem "$efile").bl" "$efile"
    [ "$rc" = 0 ] || { tail -20 "$log" >&2; die "$target $cs run $r: blink ${args[*]} exited $rc (log $log)"; }
    local sha
    sha=$(c_sha "$dir/$cfile")
    awk -v wall="$wall" -v t="$target" -v c="$cs" -v r="$r" -v sha="$sha" -v ld="$load" '
        $1 == "cc" { n++; s[n] = $2; e[n] = $3 }
        $1 == "link" { link += $3 - $2 }
        END {
            for (i = 2; i <= n; i++) {
                x = s[i]; y = e[i]
                for (j = i - 1; j >= 1 && s[j] > x; j--) { s[j + 1] = s[j]; e[j + 1] = e[j] }
                s[j + 1] = x; e[j + 1] = y
            }
            for (i = 1; i <= n; i++) {
                if (i == 1 || s[i] > hi) { if (i > 1) cc += hi - lo; lo = s[i]; hi = e[i] }
                else if (e[i] > hi) hi = e[i]
            }
            if (n > 0) cc += hi - lo
            printf "%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%s\t%s\n", t, c, r, wall, wall - cc - link, cc, link, n, sha, ld }
    ' "$work/.bench/cc.log" >> "$raw"
}

# c_sha <c file>: the hash of the C a build wrote. A per-module build writes no <stem>.c,
# so its hash covers every unit and header in <stem>.units. The path is chosen as blink
# chooses it: a flag beats BLINK_PER_MODULE, which beats the per-module default.
c_sha() {
    local f=$1 u=${1%.c}.units units=1
    case " ${BENCH_FLAGS:-} " in
        *" --no-per-module "*) units=0 ;;
        *" --per-module "*) ;;
        *) [ "${BLINK_PER_MODULE:-}" = 0 ] && units=0 ;;
    esac
    if [ "$units" = 1 ] && [ -d "$u" ]; then
        (cd "$u" && LC_ALL=C ls *.c *.h | LC_ALL=C sort | xargs cat) | sha256sum | cut -d' ' -f1
        return
    fi
    sha256sum "$f" | cut -d' ' -f1
}

# warm <target>: build, run and test once so every later case starts warm; sets base shas.
warm() {
    local target=$1 dir=$work/$(tv dir "$1") f
    for f in $(tv body "$target") "$(tv pub "$target"):-"; do
        f=${f%%:*}
        [ -f "$dir/$f" ] || die "$target: no file $f"
        cp "$dir/$f" "$work/.bench/orig/$target-$(stem "$f").bl"
    done
    for f in $(tv body "$target"); do
        [ "$(grep -c "^fn ${f#*:}(" "$dir/${f%%:*}")" = 1 ] || die "$target: need one private fn ${f#*:} in ${f%%:*}"
    done
    run_blink "$target" "$work/.bench/logs/$target-warm-build.log" build "$(tv src "$target")" ${BENCH_FLAGS:-}
    [ "$rc" = 0 ] || die "$target warm build exited $rc"
    run_blink "$target" "$work/.bench/logs/$target-warm-test.log" test "$(tv test "$target")" ${BENCH_FLAGS:-}
    [ "$rc" = 0 ] || die "$target warm test exited $rc"
    base_build=$(c_sha "$dir/build/$(stem "$(tv src "$target")").c")
    base_test=$(c_sha "$dir/build/$(stem "$(tv test "$target")").c")
    echo "bench_edit_loop: $target warm; build C $base_build, test C $base_test"
}

# summarize <target> <case> <edited> <expect same|changed> <base sha>: one TSV row.
summarize() {
    local target=$1 cs=$2 edited=$3 expect=$4 base=$5
    awk -F'\t' -v t="$target" -v c="$cs" -v ed="$edited" -v ex="$expect" -v base="$base" '
        function med(a, n,   i, j, x) {
            for (i = 2; i <= n; i++) { x = a[i]; for (j = i - 1; j >= 1 && a[j] > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
            return n % 2 ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
        }
        $1 == t && $2 == c {
            n++; w[n] = $4; e[n] = $5; cc[n] = $6; lk[n] = $7; k[n] = $8
            if (n == 1 || $4 < mn) mn = $4
            if (n == 1 || $4 > mx) mx = $4
            if ($10 > ml) ml = $10
            if (ex == "same") ok += ($9 == base)
            else if ($9 != base && !seen[$9]++) ok++
        }
        END {
            m = med(w, n)
            printf "%s\t%s\t%s\t%d\t%.3f\t%.3f\t%.3f\t%.1f\t%.3f\t%.3f\t%.3f\t%d\t%s %d/%d\t%s\n", t, c, ed, n, m, mn, mx, 100 * (mx - mn) / m, med(e, n), med(cc, n), med(lk, n), med(k, n), ex, ok, n, ml
        }
    ' "$raw" >> "$out"
    local okn
    okn=$(tail -1 "$out" | cut -f13)
    case "$okn" in
        "changed $reps/$reps"|"same $reps/$reps") ;;
        changed*) die "$target $cs: C did not change in every run ($okn); the edit is not measured" ;;
        *) echo "bench_edit_loop: WARNING $target $cs: C hash $okn (expected the warm C)" >&2 ;;
    esac
}

# run_case <target> <case> <kind> <c file> <expect> <base> [file fn]
run_case() {
    local target=$1 cs=$2 kind=$3 cfile=$4 expect=$5 base=$6 efile=${7:-} efn=${8:-} r
    case_wanted "$cs" || return 0
    echo "bench_edit_loop: $target $cs"
    for r in $(seq 1 "$reps"); do
        rep "$target" "$cs" "$r" "$cfile" "$kind" "$efile" "$efn"
    done
    summarize "$target" "$cs" "${efile:--}" "$expect" "$base"
}

{
    echo "# bench_edit_loop $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# tree $(cd "$repo" && git rev-parse --short=8 HEAD)$(cd "$repo" && git diff --quiet HEAD -- || echo ' (dirty)')"
    echo "# blink $blink_bin sha256 $(sha256sum "$blink_bin" | cut -c1-16)"
    echo "# cc $("$real_cc" --version | head -1); nproc $(nproc); reps $reps; slice ${slice:-none}"
    echo "# flags ${BENCH_FLAGS:-none}; daemon ${BENCH_DAEMON:-0}; settle ${BENCH_SETTLE:-0}s"
    echo "# emit_s = wall - cc_s - link_s; split columns are medians of their own; c_check: C hash vs the warm C"
    printf 'target\tcase\tedited\tn\tmedian_s\tmin_s\tmax_s\tspread_pct\temit_s\tcc_s\tlink_s\tcc_calls\tc_check\tmax_load1\n'
} > "$out"

for target in ${BENCH_TARGETS:-cli small}; do
    [ -n "$(tv src "$target")" ] || die "unknown target $target"
    warm "$target"
    [ "${BENCH_DAEMON:-}" = 1 ] && start_daemon "$target"
    bc=build/$(stem "$(tv src "$target")").c
    tc=build/$(stem "$(tv test "$target")").c
    run_case "$target" nochange build "$bc" same "$base_build"
    for spec in $(tv body "$target"); do
        f=${spec%%:*} fn=${spec#*:}
        run_case "$target" "body-$(modname "$f")" body "$bc" changed "$base_build" "$f" "$fn"
    done
    pf=$(tv pub "$target")
    run_case "$target" "pubfn-$(modname "$pf")" pub "$bc" changed "$base_build" "$pf"
    first=$(tv body "$target" | cut -d' ' -f1)
    f=${first%%:*} fn=${first#*:}
    run_case "$target" "run-body-$(modname "$f")" run "$bc" changed "$base_build" "$f" "$fn"
    run_case "$target" "test-body-$(modname "$f")" test "$tc" changed "$base_test" "$f" "$fn"
    run_case "$target" cold-obj cold-obj "$bc" same "$base_build"
    [ "$(tv coldall "$target")" = 1 ] && run_case "$target" cold-all cold-all "$bc" same "$base_build"
    if [ "${BENCH_DAEMON:-}" = 1 ]; then
        sed -i "1a # daemon $target served $(daemon_builds "$target") builds" "$out"
        stop_daemon
    fi
done

echo
grep '^#' "$out"
grep -v '^#' "$out" | column -t -s $'\t' 2>/dev/null || grep -v '^#' "$out"
echo "bench_edit_loop: wrote $out (per-run rows in $raw)"
