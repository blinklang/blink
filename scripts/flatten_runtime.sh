#!/bin/bash
# Concatenate the split runtime headers under bootstrap/ into one flat header a
# user .c file #includes directly (flat so the nested #includes inside the
# split headers are pre-resolved). Both bootstrap.sh (build/runtime.h, the
# legacy single-TU path) and gen1.sh (build/gen1/share/blink/runtime.h, so gen1
# stops borrowing gen0's frozen copy) call this, so the two writers cannot
# drift into two different flattenings of the same ten files.
#
#   scripts/flatten_runtime.sh <out-file>
set -u
cd "$(dirname "$0")/.." || exit 2

out="${1:?usage: scripts/flatten_runtime.sh <out-file>}"
src=bootstrap

cat "$src/runtime_core.h" \
    "$src/runtime_errno.h" \
    "$src/runtime_tcp.h" \
    "$src/runtime_unix_socket.h" \
    "$src/runtime_thread.h" \
    "$src/runtime_process.h" \
    "$src/runtime_test.h" \
    "$src/runtime_sqlite.h" \
    "$src/runtime_stdio.h" \
    "$src/runtime_term.h" \
    "$src/runtime_trace.h" \
    > "$out"
