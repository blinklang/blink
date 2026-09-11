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
#   build/gen1/share/blink/*            -> gen0's archive, header and sidecars
#   build/gen1/{blinkc,blink,libblink_std.a,libblink_std.h,skip_modules.txt}
#
# The installed layout is not cosmetic: `blink` resolves its install root
# two directories up from realpath(argv[0]), so a flat build/gen1/blink
# would resolve to build/ and link whatever archive sits there.
#
# The archive is codegen OUTPUT, so gen1 should build its own. It cannot
# until the tid-native emitters return, so share/blink/ points at gen0's.
# Every gen1 compile therefore mixes a gen0-built archive with gen1-emitted
# user C. While the emitters raise I0004 nothing is emitted to mix, so the
# corpus reads 0 passed either way. This link must be cut before a corpus
# pass count means anything: see docs/codegen-rewrite/harness.md.
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

fail=0
# compile_src <source> <c output>
compile_src() {
    src="$1"; cfile="$2"
    log="$out/$(basename "$cfile" .c).log"
    (unset BLINK_ROOT; "$gen0/blinkc" --link-archive "$archive_h" "$src" "$cfile") > "$log" 2>&1
    rc=$?
    errs=$(grep -c 'error\[' "$log" || true)
    if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ] || [ ! -s "$cfile" ]; then
        echo "gen1: FAIL gen0 does not compile $src (exit $rc, $errs error line(s)); see $log"
        grep -m5 'error\[' "$log" | sed 's/^/  /'
        fail=1
    else
        echo "gen1: ok gen0 compiles $src"
    fi
}
compile_src src/blinkc_main.bl "$out/blinkc.c"
compile_src src/cli.bl "$out/cli.c"
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
link_bin blinkc blinkc.c
link_bin blink cli.c

# Compat links for callers that still look for the tools beside the compiler rather
# than under share/blink. Guarded so a sidecar gen0 does not ship never becomes a
# dangling link that a later -e test reads as present.
ln -s bin/blinkc "$out/blinkc"
ln -s bin/blink "$out/blink"
for f in libblink_std.a libblink_std.h skip_modules.txt; do
    [ -e "$out/share/blink/$f" ] && ln -s "share/blink/$f" "$out/$f"
done
echo "gen1: built $out/bin/blinkc and $out/bin/blink"
