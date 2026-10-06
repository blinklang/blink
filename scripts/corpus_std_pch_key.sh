#!/bin/bash
# Print the key of the stdlib archive header a corpus row of compiler dir $1
# includes, then the paths of libblink_std.h and the runtime.h it includes,
# one per line, found the way corpus_one.sh links them into a sandbox. Prints
# nothing when the dir lacks either file.
#
#   scripts/corpus_std_pch_key.sh <compiler dir>
#
# gcc never checks a PCH against the headers it was built from, so the corpus
# keeps its PCH of libblink_std.h under this key of both files' contents.
set -u
comp_dir="$1"
find_file() {
    if [ -e "$comp_dir/$1" ]; then readlink -f "$comp_dir/$1"
    elif [ -e "$comp_dir/share/blink/$1" ]; then readlink -f "$comp_dir/share/blink/$1"
    fi
}
hdr=$(find_file libblink_std.h)
rt=$(find_file runtime.h)
[ -n "$hdr" ] && [ -n "$rt" ] || exit 0
key=$(sha256sum "$hdr" "$rt" | cut -d' ' -f1 | sha256sum | cut -c1-16)
printf '%s\n%s\n%s\n' "$key" "$hdr" "$rt"
