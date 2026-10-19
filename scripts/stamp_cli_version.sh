#!/usr/bin/env bash
# Usage: stamp_cli_version.sh <cli.c> <version>
#
# Sets blink_cli_version in an emitted cli.c. The whole definition line is
# rewritten, not only the literal: a compiled Str literal carries a length
# header, so a text edit of the bytes alone gives a Str whose header
# disagrees with its bytes. Fails unless exactly one definition matches, so a
# change in how codegen spells the global stops the build instead of shipping
# an unstamped or corrupt version.
set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 <cli.c> <version>" >&2
    exit 2
fi
FILE="$1"
VER="$2"

# The version goes into a C literal and a sed replacement unescaped.
if ! printf '%s' "$VER" | grep -Eq '^[A-Za-z0-9._+-]+$'; then
    echo "stamp_cli_version: ERROR version '$VER' has characters outside [A-Za-z0-9._+-]" >&2
    exit 1
fi

# A previous stamp puts the static on the same line, so a re-stamp matches it.
# The C name escapes each `_` of the Blink name as `_1`; a tree from before that
# spells it bare, and gen0.sh can still build such a tag.
DEF='^(BLINK_STR_STATIC\(blink_cli_version_lit, "[^"]*"\); )?const char\* ([A-Za-z0-9_]*blink_1?cli_1?version) = (.*);$'
N=$(grep -Ec "$DEF" "$FILE" || true)
if [ "$N" != 1 ]; then
    echo "stamp_cli_version: ERROR expected one blink_cli_version definition in $FILE, found $N" >&2
    exit 1
fi

# A tree from before the Str header emits a bare C literal and has no
# BLINK_STR_STATIC; gen0.sh can still build such a tag.
if grep -Eq '^const char\* [A-Za-z0-9_]*blink_1?cli_1?version = "[^"]*";$' "$FILE"; then
    sed -i -E "s/^const char\\* ([A-Za-z0-9_]*blink_1?cli_1?version) = \"[^\"]*\";\$/const char* \\1 = \"$VER\";/" "$FILE"
else
    sed -i -E "s/$DEF/BLINK_STR_STATIC(blink_cli_version_lit, \"$VER\"); const char* \\2 = blink_cli_version_lit.d;/" "$FILE"
fi

SYM=$(grep -Eo '[A-Za-z0-9_]*blink_1?cli_1?version = ' "$FILE" | head -1 | sed 's/ = $//')
if ! grep -Fxq "const char* $SYM = \"$VER\";" "$FILE" \
    && ! grep -Fxq "BLINK_STR_STATIC(blink_cli_version_lit, \"$VER\"); const char* $SYM = blink_cli_version_lit.d;" "$FILE"; then
    echo "stamp_cli_version: ERROR stamp not applied to $FILE" >&2
    exit 1
fi
