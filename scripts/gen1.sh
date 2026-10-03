#!/bin/bash
# Gate (a) of `task ci`, and the compiler the corpus measures: the pinned
# gen0 must compile the current compiler sources. Emits C for
# src/blinkc_main.bl and src/cli.bl with build/gen0/blinkc, then links both
# binaries against gen0's stdlib archive into build/gen1/ in the installed
# layout:
#
#   build/gen1/bin/{blinkc,blink}
#   build/gen1/lib -> <repo>/lib        stdlib SOURCES of the current tree
#   build/gen1/bin/lib -> ../lib        blinkc reads <dir of argv[0]>/lib/std
#   build/gen1/share/blink/*            gen1's own archive, header and sidecars
#                                        (runtime.h flattened fresh; native/ still
#                                        gen0's, since that's a C sidecar, not
#                                        codegen output)
#   build/gen1/{blinkc,blink,libblink_std.a,libblink_std.h,skip_modules.txt}
#
# The installed layout is not cosmetic: `blink` resolves its install root
# two directories up from realpath(argv[0]), so a flat build/gen1/blink
# would resolve to build/ and link whatever archive sits there.
#
# The archive is codegen OUTPUT: once gen1's own blinkc/blink binaries link,
# they build gen1's own archive from the current lib/std, so every corpus
# compile mixes a gen1-emitted user C with a gen1-built archive. This link to
# gen0's archive is cut; see docs/codegen-rewrite/harness.md.
#
# blinkc exits 0 even when it reports errors, so a run passes only when the
# exit code is 0 AND no `error[` line appears in its output.
#
#   scripts/gen1.sh          (env GEN0_DIR, default build/gen0)
set -u
cd "$(dirname "$0")/.." || exit 2
root="$(pwd)"
gen0="${GEN0_DIR:-build/gen0}"
out=build/gen1

if [ ! -x "$gen0/blinkc" ]; then
    echo "gen1: no gen0 compiler at $gen0 (run 'task gen0')" >&2
    exit 2
fi
[ -f build/gc_unity.c ] || ./scripts/gen_gc_unity.sh build/gc_unity.c || exit 2

rm -rf "$out"
mkdir -p "$out/bin" "$out/share/blink"
ln -s "$root/lib" "$out/lib"
ln -s ../lib "$out/bin/lib"

gen0_share="$gen0/share/blink"
[ -d "$gen0_share" ] || gen0_share="$gen0"
for f in libblink_std.a libblink_std.h skip_modules.txt runtime.h .archive-id native; do
    [ -e "$gen0_share/$f" ] && ln -s "$(readlink -f "$gen0_share/$f")" "$out/share/blink/$f"
done
archive_h="$out/share/blink/libblink_std.h"
archive_a="$out/share/blink/libblink_std.a"
if [ ! -f "$archive_h" ] || [ ! -f "$archive_a" ]; then
    echo "gen1: no stdlib archive under $gen0_share (run 'task gen0')" >&2
    exit 2
fi

# compile_src <source> <c output>; returns 1 when gen0 does not compile it.
compile_src() {
    src="$1"; cfile="$2"
    log="$out/$(basename "$cfile" .c).log"
    (unset BLINK_ROOT; "$gen0/blinkc" --link-archive "$archive_h" "$src" "$cfile") > "$log" 2>&1
    rc=$?
    errs=$(grep -c 'error\[' "$log" || true)
    if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ] || [ ! -s "$cfile" ]; then
        echo "gen1: FAIL gen0 does not compile $src (exit $rc, $errs error line(s)); see $log"
        grep -m5 'error\[' "$log" | sed 's/^/  /'
        return 1
    fi
    echo "gen1: ok gen0 compiles $src"
}
# The two compiles share nothing but their inputs, so they run side by side. Each
# PID is waited on by itself: a bare `wait` returns 0 and would hide a failure.
compile_src src/blinkc_main.bl "$out/blinkc.c" & blinkc_pid=$!
compile_src src/cli.bl "$out/cli.c" & cli_pid=$!
fail=0
wait "$blinkc_pid" || fail=1
wait "$cli_pid" || fail=1
[ "$fail" -eq 0 ] || exit 1

# link_bin <binary> <c file>
link_bin() {
    if ! cc -o "$out/bin/$1" "$out/$2" -I"$out/share/blink" "$archive_a" \
            -lm -lgc -pthread -Wl,--gc-sections > "$out/link-$1.log" 2>&1; then
        echo "gen1: FAIL cc could not link $out/bin/$1; see $out/link-$1.log"
        head -20 "$out/link-$1.log"
        exit 1
    fi
}
link_bin blinkc blinkc.c & blinkc_pid=$!
link_bin blink cli.c & cli_pid=$!
fail=0
wait "$blinkc_pid" || fail=1
wait "$cli_pid" || fail=1
[ "$fail" -eq 0 ] || exit 1

# Compat links for callers that still look for the tools beside the compiler rather
# than under share/blink. Guarded so a sidecar gen0 does not ship never becomes a
# dangling link that a later -e test reads as present.
ln -s bin/blinkc "$out/blinkc"
ln -s bin/blink "$out/blink"
for f in libblink_std.a libblink_std.h skip_modules.txt; do
    [ -e "$out/share/blink/$f" ] && ln -s "share/blink/$f" "$out/$f"
done
echo "gen1: built $out/bin/blinkc and $out/bin/blink"

# The two binaries above are still linked against gen0's archive (fine — that
# link step builds the compiler itself, not a user program). From here on,
# gen1 builds its own archive with its own blink, from the current lib/std.
#
# resolve_runtime_h() walks $BLINK_ROOT, then the install root two
# directories up from argv[0] (build/gen1 here), to share/blink/runtime.h.
# Cut gen0's symlink there first and drop in a fresh flat header built from
# this tree's bootstrap/runtime_*.h, or the archive build below would
# silently pick up gen0's frozen copy through that same lookup (it predates
# the 3-arg blink_map_remove, among other drift).
rm -f "$out/share/blink/runtime.h"
./scripts/flatten_runtime.sh "$out/share/blink/runtime.h" || exit 1

archive_log="$out/archive-build.log"
if ! BLINK_FORCE_STDLIB_REBUILD=1 "$out/bin/blink" __build-stdlib-archive > "$archive_log" 2>&1; then
    echo "gen1: FAIL gen1's own compiler could not build the stdlib archive; see $archive_log" >&2
    tail -20 "$archive_log" >&2
    exit 1
fi

# build_stdlib_archive's relink_archive writes build/{libblink_std.a,libblink_std.h,
# skip_modules.txt,.archive-id} as symlinks into build/std-cache/<hash>/, relative
# to the cwd it ran under ($root, since this script cd's there up top) — not into
# build/gen1/. That is the one place this leaves a side effect outside build/gen1
# and build/std-cache; nothing task ci/ci-fast reads depends on it (fmt-semantic,
# the one gate that reads build/libblink_std.a, runs with FMT_SEMANTIC=0 in both),
# so leaving those top-level links pointed at gen1's cache is harmless.
cache_link="$root/build/libblink_std.a"
if [ ! -L "$cache_link" ]; then
    echo "gen1: FAIL stdlib archive build did not produce $cache_link" >&2
    exit 1
fi
cache_dir="$root/build/$(dirname "$(readlink "$cache_link")")"
if [ ! -f "$cache_dir/libblink_std.a" ]; then
    echo "gen1: FAIL resolved cache dir $cache_dir has no libblink_std.a" >&2
    exit 1
fi
# runtime.h stays the flattened file dropped in above; native/ stays gen0's (C
# sidecars, not codegen output). Only the archive itself and its direct sidecars
# move to gen1's own build.
for f in libblink_std.a libblink_std.h skip_modules.txt .archive-id; do
    rm -f "$out/share/blink/$f"
    ln -s "$cache_dir/$f" "$out/share/blink/$f"
done
echo "gen1: built its own stdlib archive at $cache_dir"
