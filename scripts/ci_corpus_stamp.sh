#!/bin/bash
# Input stamp for the corpus sweep in `task ci`. The sweep takes minutes and
# its result is a pure function of the tree, the pinned compiler, the C
# compiler and the CORPUS_* settings, so `check` lets ci skip it when none of
# them changed since a sweep that passed through ci's own begin/commit pair.
# Run from the repo root.
#
#   key     print the sha256 of every input
#   begin   drop the stamp, record the key before the sweep
#   commit  keep that key as the stamp only if the tree is unchanged since
#           begin, so an edit made mid-run never earns a stamp
#   check   exit 0 only if the stamp matches the key now and no output file
#           was rewritten after it (another corpus run does that)
#
# The tree hash is a deny-list: a new kind of input that nobody listed still
# busts the stamp. Only paths no corpus test reads are left out. sections/ is
# one: the spec leads the compiler, so a corpus test may not read it, and the
# ratchet, which runs on every ci, holds the spec checks.
set -u

STAMP=build/ci_corpus.stamp
PENDING=build/ci_corpus.pending
OUTPUTS=${CI_STAMP_OUTPUTS:-"build/corpus.json build/corpus_per_module_slice.json"}

key() {
    {
        git ls-files -z -c -o --exclude-standard | sort -zu | while IFS= read -r -d '' f; do
            case "$f" in
                sections/*|decisions/*|docs/*|DECISIONS.md|OPEN_QUESTIONS.md) continue ;;
            esac
            [ -f "$f" ] || continue
            printf '%s\0' "$f"
        done | xargs -0 -r sha256sum --
        for f in build/gen0/bin/blinkc build/gen0/bin/blink; do
            [ -f "$f" ] && sha256sum -- "$f"
        done
        cc --version 2>&1
        echo "BLINK_GEN0_SEED=${BLINK_GEN0_SEED-}"
        env | grep '^CORPUS_' | LC_ALL=C sort
    } | sha256sum | cut -d' ' -f1
}

case "${1:-}" in
    key)
        key
        ;;
    begin)
        mkdir -p build
        rm -f "$STAMP"
        key > "$PENDING"
        ;;
    commit)
        if [ -f "$PENDING" ] && [ "$(cat "$PENDING")" = "$(key)" ]; then
            # The sweep wrote the outputs after begin; the stamp must be newer.
            mv "$PENDING" "$STAMP"
            touch "$STAMP"
        else
            rm -f "$PENDING" "$STAMP"
            echo "ci_corpus_stamp: tree changed during the run, no stamp written"
        fi
        exit 0
        ;;
    check)
        [ -f "$STAMP" ] || exit 1
        [ "$(cat "$STAMP")" = "$(key)" ] || exit 1
        for out in $OUTPUTS; do
            [ -f "$out" ] || exit 1
            ! [ "$out" -nt "$STAMP" ] || exit 1
        done
        exit 0
        ;;
    *)
        echo "usage: ci_corpus_stamp.sh key|begin|commit|check" >&2
        exit 2
        ;;
esac
