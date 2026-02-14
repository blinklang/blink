#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

mkdir -p "$BUILD_DIR"
cp "$SCRIPT_DIR/runtime.h" "$BUILD_DIR/runtime.h"
mkdir -p "$BUILD_DIR/lib/std"
cp "$ROOT_DIR/lib/std/"*.pact "$BUILD_DIR/lib/std/"

echo "Compiling bootstrap compiler..."
cc -o "$BUILD_DIR/pactc" "$SCRIPT_DIR/pactc_bootstrap.c" -lm

echo "Self-compiling pactc..."
"$BUILD_DIR/pactc" "$ROOT_DIR/src/compiler.pact" "$BUILD_DIR/pactc_self.c"
cc -o "$BUILD_DIR/pactc_self" "$BUILD_DIR/pactc_self.c" -lm

echo "Verifying bootstrap chain..."
"$BUILD_DIR/pactc_self" "$ROOT_DIR/src/compiler.pact" "$BUILD_DIR/pactc_verify.c"
if diff -q "$BUILD_DIR/pactc_self.c" "$BUILD_DIR/pactc_verify.c" > /dev/null 2>&1; then
    echo "Bootstrap verified — self-compilation is stable."
    cp "$BUILD_DIR/pactc_self" "$BUILD_DIR/pactc"
    rm -f "$BUILD_DIR/pactc_self" "$BUILD_DIR/pactc_self.c" "$BUILD_DIR/pactc_verify.c"
else
    echo "ERROR: Bootstrap verification failed — gen1 and gen2 differ!" >&2
    exit 1
fi

echo "Done. Compiler at: $BUILD_DIR/pactc"
