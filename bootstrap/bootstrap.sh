#!/bin/sh
set -e

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
    "$SCRIPT_DIR/runtime_trace.h" \
    > "$BUILD_DIR/runtime.h"
mkdir -p "$BUILD_DIR/lib/std"
cp "$ROOT_DIR/lib/std/"*.pact "$BUILD_DIR/lib/std/"
mkdir -p "$BUILD_DIR/lib/pkg"
cp "$ROOT_DIR/lib/pkg/"*.pact "$BUILD_DIR/lib/pkg/"

# --- Gen 0: resolve a working pactc ---
GEN0=""
if [ -f "$BUILD_DIR/pactc" ]; then
    echo "Using existing build/pactc as Gen 0"
    GEN0="$BUILD_DIR/pactc"
elif command -v pact > /dev/null 2>&1; then
    echo "Compiling pactc from installed pact..."
    pact build "$ROOT_DIR/src/pactc_main.pact" --output "$BUILD_DIR/pactc_gen0"
    GEN0="$BUILD_DIR/pactc_gen0"
else
    echo "ERROR: No compiler found." >&2
    echo "Either build/pactc must exist, or 'pact' must be on PATH." >&2
    echo "Install pact from: https://github.com/nhumrich/pact/releases" >&2
    exit 1
fi

# --- Gen 1: compile pactc with Gen 0 ---
echo "Self-compiling pactc (Gen 1)..."
"$GEN0" "$ROOT_DIR/src/pactc_main.pact" "$BUILD_DIR/pactc_gen1.c"
cc -o "$BUILD_DIR/pactc_gen1" "$BUILD_DIR/pactc_gen1.c" -lm

# --- Gen 2: compile pactc with Gen 1 ---
echo "Verifying bootstrap chain (Gen 2)..."
"$BUILD_DIR/pactc_gen1" "$ROOT_DIR/src/pactc_main.pact" "$BUILD_DIR/pactc_gen2.c"

if diff -q "$BUILD_DIR/pactc_gen1.c" "$BUILD_DIR/pactc_gen2.c" > /dev/null 2>&1; then
    echo "Bootstrap verified — self-compilation is stable."
    rm -f "$BUILD_DIR/pactc"
    cp "$BUILD_DIR/pactc_gen1" "$BUILD_DIR/pactc"
    rm -f "$BUILD_DIR/pactc_gen0" "$BUILD_DIR/pactc_gen1" "$BUILD_DIR/pactc_gen1.c" "$BUILD_DIR/pactc_gen2.c"
else
    echo "ERROR: Bootstrap verification failed — Gen 1 and Gen 2 differ!" >&2
    exit 1
fi

echo "Done. Compiler at: $BUILD_DIR/pactc"
