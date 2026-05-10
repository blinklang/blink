#!/bin/sh
set -e

# Legacy escape hatch — keep one revision's worth of fallback while the
# archive-based bootstrap proves itself in CI.
if [ -n "$BLINK_BOOTSTRAP_LEGACY" ]; then
    exec "$(dirname "$0")/bootstrap_legacy.sh"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

mkdir -p "$BUILD_DIR"
# Copy split runtime headers to build/ for direct #include usage
cp "$SCRIPT_DIR"/runtime_*.h "$BUILD_DIR/"
# Build a flat runtime.h in build/ for CLI inlining (CLI reads build/runtime.h
# and embeds it verbatim in generated C, so nested #includes won't work)
cat "$SCRIPT_DIR/runtime_core.h" \
    "$SCRIPT_DIR/runtime_tcp.h" \
    "$SCRIPT_DIR/runtime_unix_socket.h" \
    "$SCRIPT_DIR/runtime_thread.h" \
    "$SCRIPT_DIR/runtime_process.h" \
    "$SCRIPT_DIR/runtime_test.h" \
    "$SCRIPT_DIR/runtime_sqlite.h" \
    "$SCRIPT_DIR/runtime_stdio.h" \
    "$SCRIPT_DIR/runtime_term.h" \
    "$SCRIPT_DIR/runtime_trace.h" \
    > "$BUILD_DIR/runtime.h"
# Build gc_unity.c — inline all ../*.c includes from gc/extra/gc.c into a
# single translation unit so the embedded version has no relative .c deps.
GC_EXTRA="$SCRIPT_DIR/vendor/gc/extra"
GC_UNITY="$BUILD_DIR/gc_unity.c"
# Inline all #include "../*.c" directives (POSIX-compatible, no gawk needed)
while IFS= read -r line; do
    inc_path=$(printf '%s\n' "$line" | sed -n 's/^#[[:space:]]*include[[:space:]]*"\(\.\.\/[^"]*\.c\)".*/\1/p')
    if [ -n "$inc_path" ]; then
        echo "/* === inlined: $inc_path === */"
        cat "$GC_EXTRA/$inc_path"
        echo "/* === end: $inc_path === */"
    else
        printf '%s\n' "$line"
    fi
done < "$GC_EXTRA/gc.c" > "$GC_UNITY"

mkdir -p "$BUILD_DIR/lib/std"
cp "$ROOT_DIR/lib/std/"*.bl "$BUILD_DIR/lib/std/"
mkdir -p "$BUILD_DIR/lib/pkg"
cp "$ROOT_DIR/lib/pkg/"*.bl "$BUILD_DIR/lib/pkg/"

# --- Gen 0: resolve a working compiler PAIR ---
#
# Two-stage gen0: we need both a bare blinkc (to emit gen1.c) and a
# blink CLI (to call __build-stdlib-archive). Existing build/* are
# preferred; otherwise host `blink` builds fresh gen0 binaries.
GEN0_BLINKC=""
GEN0_BLINK=""
if [ -f "$BUILD_DIR/blinkc" ] && [ -x "$BUILD_DIR/blink" ]; then
    echo "Using existing build/blinkc + build/blink as Gen 0"
    GEN0_BLINKC="$BUILD_DIR/blinkc"
    GEN0_BLINK="$BUILD_DIR/blink"
elif command -v blink > /dev/null 2>&1; then
    echo "Compiling Gen 0 blinkc + blink from installed blink..."
    blink build "$ROOT_DIR/src/blinkc_main.bl" --output "$BUILD_DIR/blinkc_gen0"
    blink build "$ROOT_DIR/src/cli.bl"         --output "$BUILD_DIR/blink_gen0"
    GEN0_BLINKC="$BUILD_DIR/blinkc_gen0"
    GEN0_BLINK="$BUILD_DIR/blink_gen0"
else
    echo "ERROR: No compiler found." >&2
    echo "Either build/blinkc + build/blink must exist, or 'blink' must be on PATH." >&2
    echo "Install blink from: https://github.com/blinklang/blink/releases" >&2
    exit 1
fi

# --- Stdlib archive (gen0 builds it; gen1+gen2 reuse) ---
echo "Building stdlib archive..."
"$GEN0_BLINK" __build-stdlib-archive

# --- Gen 1: compile blinkc against the archive ---
echo "Self-compiling blinkc (Gen 1)..."
"$GEN0_BLINKC" --link-archive "$BUILD_DIR/libblink_std.h" \
    "$ROOT_DIR/src/blinkc_main.bl" "$BUILD_DIR/blinkc_gen1.c"
cc -o "$BUILD_DIR/blinkc_gen1" "$BUILD_DIR/blinkc_gen1.c" \
    -I"$BUILD_DIR" "$BUILD_DIR/libblink_std.a" -lm -lgc -pthread -Wl,--gc-sections

# --- Gen 2: same, with gen1 blinkc ---
echo "Verifying bootstrap chain (Gen 2)..."
"$BUILD_DIR/blinkc_gen1" --link-archive "$BUILD_DIR/libblink_std.h" \
    "$ROOT_DIR/src/blinkc_main.bl" "$BUILD_DIR/blinkc_gen2.c"

if ! diff -q "$BUILD_DIR/blinkc_gen1.c" "$BUILD_DIR/blinkc_gen2.c" > /dev/null 2>&1; then
    echo "ERROR: Bootstrap verification failed — Gen 1 and Gen 2 .c differ!" >&2
    exit 1
fi

# Archive determinism: extract monolith.o, force a rebuild, extract again,
# and bit-compare. Tests the layer under our control (monolith.c + cc),
# sidestepping ar/strip-nondeterminism platform variation.
ARCH_CHECK_DIR="$BUILD_DIR/.archive-check"
mkdir -p "$ARCH_CHECK_DIR"
ar p "$BUILD_DIR/libblink_std.a" monolith.o > "$ARCH_CHECK_DIR/mono1.o"
BLINK_FORCE_STDLIB_REBUILD=1 "$GEN0_BLINK" __build-stdlib-archive
ar p "$BUILD_DIR/libblink_std.a" monolith.o > "$ARCH_CHECK_DIR/mono2.o"
if ! cmp "$ARCH_CHECK_DIR/mono1.o" "$ARCH_CHECK_DIR/mono2.o" > /dev/null 2>&1; then
    echo "ERROR: stdlib archive monolith.o is not deterministic across rebuilds!" >&2
    exit 1
fi
rm -rf "$ARCH_CHECK_DIR"

echo "Bootstrap verified — self-compilation is stable."
rm -f "$BUILD_DIR/blinkc"
cp "$BUILD_DIR/blinkc_gen1" "$BUILD_DIR/blinkc"
rm -f "$BUILD_DIR/blinkc_gen0" "$BUILD_DIR/blink_gen0" \
    "$BUILD_DIR/blinkc_gen1" "$BUILD_DIR/blinkc_gen1.c" "$BUILD_DIR/blinkc_gen2.c"

echo "Done. Compiler at: $BUILD_DIR/blinkc"
