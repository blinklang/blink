#!/bin/bash
# Gate (a) of `task ci`: the pinned gen0 compiler must compile the current
# compiler sources. Emits C for src/blinkc_main.bl and src/cli.bl with
# build/gen0/blinkc, then links build/gen1/blinkc against gen0's stdlib
# archive so later ci steps (formatter goldens) can drive the CURRENT
# compiler. build/gen1/lib points at the repo lib/ because blinkc reads its
# stdlib from <dir of argv[0]>/lib/std.
#
# blinkc exits 0 even when it reports errors, so a run passes only when the
# exit code is 0 AND no `error[` line appears in its output.
#
#   scripts/gen1.sh          (env GEN0_DIR, default build/gen0)
set -u
cd "$(dirname "$0")/.."
gen0="${GEN0_DIR:-build/gen0}"
out=build/gen1

if [ ! -x "$gen0/blinkc" ]; then
    echo "gen1: no gen0 compiler at $gen0 (run 'task gen0')" >&2
    exit 2
fi
mkdir -p "$out"
[ -f build/gc_unity.c ] || ./scripts/gen_gc_unity.sh build/gc_unity.c || exit 2
rm -f "$out/lib"
ln -s "$(pwd)/lib" "$out/lib"

archive_h="$gen0/share/blink/libblink_std.h"
archive_a="$gen0/share/blink/libblink_std.a"
[ -f "$archive_h" ] || archive_h="$gen0/libblink_std.h"
[ -f "$archive_a" ] || archive_a="$gen0/libblink_std.a"

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

if ! cc -o "$out/blinkc" "$out/blinkc.c" -I"$(dirname "$archive_h")" "$archive_a" -lm -lgc -pthread -Wl,--gc-sections > "$out/link.log" 2>&1; then
    echo "gen1: FAIL cc could not link $out/blinkc; see $out/link.log"
    head -20 "$out/link.log"
    exit 1
fi
echo "gen1: built $out/blinkc"
