#!/usr/bin/env bash
# cc_unit.sh <blinkc> <cc> [cflags...] -- <file.c>... -- [link args...]
#
# Compiles C that blinkc emitted with the -D flags that `blink build` gives the same C under
# the same compiler. The C declares each foreign prototype inside
# `#ifndef BLINK_DECLARED_<sym>`, and spells each @ffi.struct type through a macro; only a
# probe of the C under that compiler can say which flags it needs.
#
# The words before the first `--` are the compile words: the C compiler and the flags that
# change what it reads (-I, -D, -target, -O). The probe gets these words, so they must not
# hold an output, an input file or a link flag; those go after the second `--`. When the
# probe gives no verdict, blinkc says why and this script exits 1 before any compile.
#
# Each unit has its own verdict, so with two or more C files each compiles alone with its
# own flags, one after another as a single cc line would, and one more cc line links the
# objects.
set -eu

usage() {
    echo "usage: cc_unit.sh <blinkc> <cc> [cflags...] -- <file.c>... -- [link args...]" >&2
    exit 2
}

[ "$#" -ge 3 ] || usage
blinkc="$1"
shift
compile=()
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    compile+=("$1")
    shift
done
[ "$#" -gt 0 ] || usage
shift
units=()
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    units+=("$1")
    shift
done
[ "$#" -gt 0 ] && shift
[ "${#compile[@]}" -gt 0 ] && [ "${#units[@]}" -gt 0 ] || usage

# A blinkc from before gen0-29 has no --build-probe-flags. Stop here with the pin it needs,
# not later with a cc error on a conflicting prototype.
if [ ! -x "$blinkc" ]; then
    echo "cc_unit.sh: $blinkc is not an executable file" >&2
    exit 1
fi
if ! "$blinkc" </dev/null 2>&1 | grep -q -- --build-probe-flags; then
    echo "cc_unit.sh: $blinkc has no --build-probe-flags; use a blinkc from gen0-29 or later" >&2
    exit 1
fi

# The flags of one unit, or exit 1 with blinkc's reason.
probe_flags() {
    local flags
    if ! flags=$("$blinkc" --build-probe-flags "$1" "${compile[@]}"); then
        echo "cc_unit.sh: no build probe flags for $1; nothing compiled" >&2
        exit 1
    fi
    printf '%s' "$flags"
}

if [ "${#units[@]}" -eq 1 ]; then
    flags=$(probe_flags "${units[0]}") || exit 1
    # shellcheck disable=SC2086 # the flags are -D words with no spaces
    exec "${compile[@]}" $flags "${units[0]}" "$@"
fi

objs=$(mktemp -d "${TMPDIR:-/tmp}/cc_unit.XXXXXX")
trap 'rm -rf "$objs"' EXIT
objects=()
i=0
for u in "${units[@]}"; do
    flags=$(probe_flags "$u") || exit 1
    # shellcheck disable=SC2086
    "${compile[@]}" $flags -c -o "$objs/$i.o" "$u"
    objects+=("$objs/$i.o")
    i=$((i + 1))
done
"${compile[@]}" "${objects[@]}" "$@"
