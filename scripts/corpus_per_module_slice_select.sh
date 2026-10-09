#!/bin/bash
# Print the test files the per-module slice rule picks, one path per line,
# sorted. scripts/corpus_per_module_slice.txt holds these plus a few
# single-file programs picked by hand; refresh it from this output.
#
#   scripts/corpus_per_module_slice_select.sh
#
# The rule: a tests/test_*.bl file joins the slice when it
#   (a) imports a module that is neither std nor part of the compiler: a
#       helper module beside the compiler sources, or a lib/pkg module;
#   (b) builds a program of more than one module through the CLI: it runs
#       the CLI on a source it writes that imports such a module, calls an
#       _xmod helper of compile_test_helpers, or names a tests/multifile* or
#       tests/zz*_calls program;
#   (c) runs `blink test` through the CLI; or
#   (d) tests the per-module build, its emit or unit reuse, or the obj cache:
#       its name says per_module, objcache or obj_cache.
# "Part of the compiler" is the import closure of src/blinkc_main.bl and
# src/cli.bl, plus the test helpers that drive it (compile_test_helpers and
# the cg, lower and cname test helpers). A file that imports only those is one
# program over the compiler, which the full per-module corpus in ci-release
# covers; in units it costs several seconds a file.
set -u
cd "$(dirname "$0")/.." || exit 2

imports_of() { sed -n 's/^import \([a-z_][a-z_0-9]*\).*/\1/p' "$1" | sort -u; }

compiler=$(mktemp)
queue="blinkc_main cli compile_test_helpers cg_test_helpers lower_test_helpers cname_test_helpers"
while [ -n "$queue" ]; do
    set -- $queue
    m=$1; shift; queue="$*"
    grep -qx "$m" "$compiler" && continue
    echo "$m" >> "$compiler"
    for i in $(imports_of "src/$m.bl"); do
        [ -f "src/$i.bl" ] && ! grep -qx "$i" "$compiler" && queue="$queue $i"
    done
done
echo std >> "$compiler"

# One grep per test over the whole tree, not several per file: ci runs this
# beside the gen1 build, and forking per file cost it seconds.
work=$(mktemp -d)
trap 'rm -f "$compiler"; rm -rf "$work"' EXIT
ls src/*.bl | sed 's|^src/||; s|\.bl$||' > "$work/src"
for d in lib/*/; do [ -d "$d" ] && basename "$d"; done > "$work/lib"
grep -oHE '^import [a-z_][a-z_0-9]*' tests/test_*.bl | sed 's/:import /\t/' > "$work/imports"
grep -lE 'build/blink|blink_bin|"blink"' tests/test_*.bl > "$work/cli"
# The imports of the sources a test writes, from its string literals.
grep -oHE '(^|\\n|")import [a-z_][a-z_0-9]*' tests/test_*.bl | sed 's/:.*import /\t/' > "$work/staged"
grep -lE '_xmod\(|tests/(multifile|zz[a-z]*_calls)' tests/test_*.bl > "$work/multi"
grep -lE '\["test"|blink test ' tests/test_*.bl > "$work/test"
ls tests/test_*.bl | grep -E '/[^/]*(per_module|objcache|obj_cache)[^/]*$' > "$work/named"

awk -F'\t' '
    FILENAME == ARGV[1] { compiler[$1] = 1; next }
    FILENAME == ARGV[2] { src[$1] = 1; next }
    FILENAME == ARGV[3] { lib[$1] = 1; next }
    FILENAME == ARGV[4] { if (!($2 in compiler) && (($2 in src) || ($2 in lib))) pick[$1] = 1; next }
    FILENAME == ARGV[5] { cli[$1] = 1; next }
    FILENAME == ARGV[6] { if (($1 in cli) && !($2 in compiler)) pick[$1] = 1; next }
    { pick[$1] = 1 }
    END { for (f in pick) print f }
' "$compiler" "$work/src" "$work/lib" "$work/imports" "$work/cli" "$work/staged" \
    "$work/multi" "$work/test" "$work/named" | LC_ALL=C sort
