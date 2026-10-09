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
# The imports of the sources a test writes, from its string literals.
staged_imports_of() {
    grep -oE '(^|\\n|")import [a-z_][a-z_0-9]*' "$1" | sed 's/.*import //' | sort -u
}

compiler=$(mktemp)
trap 'rm -f "$compiler"' EXIT
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

for f in tests/test_*.bl; do
    pick=0
    for i in $(imports_of "$f"); do
        grep -qx "$i" "$compiler" && continue
        if [ -f "src/$i.bl" ] || [ -d "lib/$i" ]; then pick=1; break; fi
    done
    if [ "$pick" -eq 0 ] && grep -qE 'build/blink|blink_bin|"blink"' "$f"; then
        for i in $(staged_imports_of "$f"); do
            grep -qx "$i" "$compiler" && continue
            pick=1; break
        done
    fi
    if [ "$pick" -eq 0 ]; then
        if grep -qE '_xmod\(|tests/(multifile|zz[a-z]*_calls)' "$f"; then pick=1
        elif grep -qE '\["test"|blink test ' "$f"; then pick=1
        else
            case "$(basename "$f")" in *per_module*|*objcache*|*obj_cache*) pick=1 ;; esac
        fi
    fi
    [ "$pick" -eq 1 ] && echo "$f"
done | LC_ALL=C sort
