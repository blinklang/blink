#!/bin/bash
# The check-clean row of `task ci`: a program that `blink check` accepts must
# build (spec §6.7.1, §6.7.6). Each program runs in a private copy of its
# directory with the same default flags for both commands, so the only shared
# state is the compiler.
#
# Sweeps tests/check_clean/ (<name>.bl, or a package <name>/src/main.bl) and
# examples/*.bl with gen1.
#
# The copy has two reasons. A build writes build/ into its cwd, and a vendored
# native dependency's path resolves against the cwd, so the cwd must be the
# package root and must not be the tree. A relative entry path also keeps the
# verdict the same wherever the checkout lives: from an absolute path, the
# compiler takes the first /src/ in the path as the module root.
#
# Does not cover:
#   - tests/test_*.bl: about 18 minutes under `blink build`, and the corpus
#     already builds and runs each one;
#   - a program that a test holds as a string, which check on the test file
#     does not see;
#   - code that only a test block reaches, since `blink build` leaves it out;
#   - run-time behaviour, and flags other than the default;
#   - §6.7.2's promise that the cwd is not an input, since the row uses one cwd;
#   - a package with a path dependency outside its own directory, such as
#     examples/with_deps/app: the copy does not hold it;
#   - a program that check wrongly rejects and that is not on the list: the row
#     does not judge it, and the corpus covers that fault.
#
# A generic fn in a judged program needs at least one instance (§6.7.6), or the
# build types only its signature. An author must keep to this; the row does not
# test it.
#
# Verdict of one program:
#   check 1                          not judged, named in the summary
#   check other than 0 or 1          red: the check did not run clean
#   build 0 and an executable output ok
#   build 0 and no such output       red: exit 0 must mean a binary
#   build 1, each error in §6.7.3,
#     and the program has a C side   outside cause, not red
#   build 1, any other error         red, labelled apart from an ICE: §6.7.1
#                                    calls any other stop a compiler bug
#   build 101, signal or time limit  red
#
# A program with no `@ffi` and no native dependency in its manifest has no C
# side, so the §6.7.3 causes cannot apply: the label comes from the compiler,
# and a compiler fault can carry it. A program that reaches a system library
# only through a std module needs an `@ffi` of its own to count as outside. A
# link failure that names `main` or a `blink_` symbol is the compiler's, with or
# without a C side.
#
# A line on the known-failure list accepts one stop: the name at the start of
# its reason, `ICE <Name>:` for an internal compiler error or `<Name>:` for an
# error. Any other result of a listed program is red: a build, a check that
# rejects it, an outside cause, another name, a signal, a time limit or no
# binary. A new fault with the same name stays green, as the row compares only
# the name. A listed file that is gone goes red too.
# scripts/check_clean_shrink.sh makes the list fail the gate when it grows.
#
#   scripts/check_clean.sh
#
# Env:
#   CHECK_CLEAN_BLINK  the compiler (default build/gen1/bin/blink)
#   CHECK_CLEAN_ROOT   the tree to sweep (default this repo), for the self-test
#   CHECK_CLEAN_RESULT a file for the green result line, so that a task that
#                      skips this sweep can still say what it last proved
#   CHECK_CLEAN_BUILD_LIMIT  seconds for one build (default 300), for the self-test
#
# Exit 0 green, 1 red, 2 when the row cannot judge: no compiler, a missing or
# malformed list, a package with no entry file, a worker that gave no verdict, or
# no program judged at all.
set -u
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
root=$(cd "${CHECK_CLEAN_ROOT:-$script_dir/..}" && pwd) || exit 2
blink="${CHECK_CLEAN_BLINK:-$root/build/gen1/bin/blink}"
case "$blink" in /*) ;; *) blink="$root/$blink" ;; esac
list="$root/scripts/check_clean_known_failures.txt"
capped="$script_dir/capped.sh"

if [ ! -x "$blink" ]; then
    echo "check-clean: no compiler at $blink (run 'task gen1')" >&2
    exit 2
fi
if [ ! -f "$list" ]; then
    echo "check-clean: no known-failure list at $list" >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
start=$(date +%s.%N)

# Each line is `<path> <stop>: <what fails>`. A line with no stop name cannot say
# what the row accepts, and a repeated path would let one removal leave it listed.
bad=$(awk '!/^[[:space:]]*(#|$)/ {
    if (NF < 2) print "no reason: " $0
    else if (seen[$1]++) print "listed twice: " $1
    else if (($2 == "ICE" ? $3 : $2) !~ /^[A-Za-z0-9_]+:$/) print "no stop name: " $0
}' "$list")
if [ -n "$bad" ]; then
    echo "check-clean: malformed list $list:" >&2
    printf '%s\n' "$bad" >&2
    exit 2
fi
awk '!/^[[:space:]]*(#|$)/ {
    stop = ($2 == "ICE" ? "ICE " $3 : $2)
    sub(/:$/, "", stop)
    print $1 "\t" stop
}' "$list" | LC_ALL=C sort > "$work/listed"

: > "$work/programs"
for f in "$root"/tests/check_clean/*.bl "$root"/examples/*.bl; do
    [ -f "$f" ] && printf '%s\n' "${f#"$root"/}" >> "$work/programs"
done
for d in "$root"/tests/check_clean/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    if [ ! -f "$d/src/main.bl" ]; then
        echo "check-clean: package ${d#"$root"/} has no src/main.bl" >&2
        exit 2
    fi
    printf '%s\n' "${d#"$root"/}/src/main.bl" >> "$work/programs"
done
LC_ALL=C sort -o "$work/programs" "$work/programs"

# One line on stdout: <path> TAB <verdict> TAB <detail>. A worker that cannot set
# up gives no line, and the count check below stops the row.
judge_one() {
    path="$1"
    case "$path" in
        */src/main.bl) from="${path%/src/main.bl}" entry=src/main.bl ;;
        *) from="${path%/*}" entry="${path##*/}" ;;
    esac
    w=$(mktemp -d "$CHECK_CLEAN_WORK/w.XXXXXX") || return
    cp -r "$CHECK_CLEAN_TREE/$from" "$w/p" || return
    cd "$w/p" || return
    "$CHECK_CLEAN_CAPPED" --child --timeout 120 "$CHECK_CLEAN_BLINKBIN" check "$entry" > "$w/c.out" 2>&1
    c=$?
    if [ "$c" = 1 ]; then
        printf '%s\trejected\t\n' "$path"
    elif [ "$c" != 0 ]; then
        printf '%s\tcheck-abnormal\tcheck exit %s: %s\n' "$path" "$c" "$(first_stop "$w/c.out")"
    else
        "$CHECK_CLEAN_CAPPED" --child --timeout "$CHECK_CLEAN_BUILD_LIMIT" "$CHECK_CLEAN_BLINKBIN" build -o "$w/out" "$entry" > "$w/b.out" 2>&1
        b=$?
        if [ "$b" = 0 ]; then
            if [ -f "$w/out" ] && [ -x "$w/out" ]; then
                printf '%s\tbuilt\t\n' "$path"
            else
                printf '%s\tfailed\tbuild exit 0, no executable output\n' "$path"
            fi
        elif [ "$b" = 1 ]; then
            if is_outside "$w/b.out" && has_c_side "$path"; then
                printf '%s\toutside\t%s\n' "$path" "$(error_names "$w/b.out" | tr '\n' ' ')"
            else
                printf '%s\tfailed\ta stop that §6.7.3 does not list: build exit 1: %s\n' "$path" "$(first_stop "$w/b.out")"
            fi
        else
            printf '%s\tfailed\tbuild exit %s: %s\n' "$path" "$b" "$(first_stop "$w/b.out")"
        fi
    fi
    cd / && rm -rf "$w"
}
error_names() { sed -n 's/^error\[\([A-Za-z0-9_]*\)\].*/\1/p' "$1" | LC_ALL=C sort -u; }
# Each error line must carry a §6.7.3 name. A line in another form, or a link
# failure on a symbol the compiler owns, is not a cause on the host.
is_outside() {
    [ -n "$(error_names "$1")" ] || return 1
    error_names "$1" | grep -qvxE 'ForeignHeaderNotFound|ForeignConstInvalid|LinkFailed|NativeDependencyBuildFailed' && return 1
    grep -qE '^(error:|internal compiler error)' "$1" && return 1
    grep -qE 'undefined reference to [^[:alnum:]_]*(main|blink_)' "$1" && return 1
    return 0
}
# Line-start anchors, so that a comment that names `@ffi` gives no C side.
has_c_side() {
    case "$1" in
        */src/main.bl)
            pkg="$CHECK_CLEAN_TREE/${1%/src/main.bl}"
            grep -rqE '^[[:space:]]*@ffi' "$pkg/src" || grep -qE '^[[:space:]]*\[native-dependencies\]' "$pkg/blink.toml" 2>/dev/null
            ;;
        *) grep -qE '^[[:space:]]*@ffi' "$CHECK_CLEAN_TREE/$1" ;;
    esac
}
first_stop() {
    line=$(grep -m1 -E '^(error|internal compiler error)' "$1")
    [ -n "$line" ] || line=$(tail -n 1 "$1")
    printf '%s' "$line" | cut -c1-200
}
export -f judge_one error_names is_outside has_c_side first_stop
export CHECK_CLEAN_WORK="$work" CHECK_CLEAN_CAPPED="$capped" CHECK_CLEAN_BLINKBIN="$blink" CHECK_CLEAN_TREE="$root"
export CHECK_CLEAN_BUILD_LIMIT="${CHECK_CLEAN_BUILD_LIMIT:-300}"

# The row must judge the compiler's own defaults, not a mode a caller set. The
# CHILD and GATE settings are capped.sh's, not the compiler's.
for v in $(compgen -e | grep '^BLINK_' | grep -vE '^BLINK_(CHILD|GATE)_'); do unset "$v"; done
# Each worker runs one cc at a time beside the corpus, so 4 workers at most, and
# fewer when the gate budget is smaller. See docs/build/gate-memory-budget.md.
workers=$("$script_dir/default_jobs.sh") || exit 2
[ "$workers" -gt 4 ] && workers=4
export BLINK_JOBS=1
export GC_MARKERS="${GC_MARKERS:-1}"

# A step beside this row that fails makes task stop it with INT, then kill it
# about 2 s later, and the sweep would run on to the end with no one to read it.
# Each process of the sweep has its cwd under $work, and timeout puts each child
# in a group of its own, so this finds them by cwd and not by group. Xargs is one
# of them, so a pass stops new workers, and the next pass takes what the last forked.
stop_sweep() {
    trap - INT TERM
    for _ in 1 2 3 4 5; do
        pids=$(find /proc/[0-9]*/cwd -maxdepth 0 \( -lname "$work" -o -lname "$work/*" \) 2>/dev/null | awk -F/ '{ print $3 }')
        [ -n "$pids" ] || break
        kill -KILL $pids 2>/dev/null
    done
    rm -rf "$work"
    exit "$1"
}
trap 'stop_sweep 130' INT
trap 'stop_sweep 143' TERM
# In the background, so that a trapped signal runs the handler at once.
(cd "$work" && exec xargs -P "$workers" -I{} bash -c 'judge_one "$1"' _ {}) < "$work/programs" > "$work/results" &
wait $!

if [ "$(wc -l < "$work/results")" != "$(wc -l < "$work/programs")" ]; then
    echo "check-clean: $(wc -l < "$work/programs") programs but $(wc -l < "$work/results") verdicts" >&2
    exit 2
fi
LC_ALL=C sort -o "$work/results" "$work/results"

fail=0
built=0 known=0 outside=0
rejected=""
stale() {
    if [ -n "$want" ]; then
        echo "check-clean: RED $path: on the list but $1; take its line off"
        fail=1
    fi
}
# The name of a stop the list can accept, from a `failed` verdict's detail. A
# signal, a time limit or no binary has none, so a list line cannot accept it.
stop_of() {
    sed -nE 's/^build exit 101: internal compiler error\[([A-Za-z0-9_]+)\].*/ICE \1/p; s/.*build exit 1: error\[([A-Za-z0-9_]+)\].*/\1/p' <<< "$1"
}
while IFS=$'\t' read -r path verdict detail; do
    want=$(awk -F'\t' -v p="$path" '$1 == p { print $2 }' "$work/listed")
    case "$verdict" in
        built)
            built=$((built + 1))
            stale "it builds now"
            ;;
        rejected)
            rejected="$rejected ${path#tests/check_clean/}"
            stale "check rejects it now"
            ;;
        outside)
            outside=$((outside + 1))
            echo "check-clean: outside cause $path: $detail"
            stale "its stop is an outside cause now"
            ;;
        check-abnormal)
            echo "check-clean: RED $path: the check did not run clean: $detail"
            fail=1
            ;;
        *)
            if [ -z "$want" ]; then
                echo "check-clean: RED $path: check passed, then $detail"
                fail=1
            elif [ "$(stop_of "$detail")" = "$want" ]; then
                known=$((known + 1))
            else
                echo "check-clean: RED $path: on the list for $want, but now: $detail"
                fail=1
            fi
            ;;
    esac
done < "$work/results"

for path in $(cut -f1 "$work/listed" | LC_ALL=C comm -23 - "$work/programs"); do
    echo "check-clean: RED $path: on the list but the row does not sweep it; is the file gone?"
    fail=1
done

judged=$((built + known + outside))
secs=$(printf '%.1f' "$(echo "$(date +%s.%N) - $start" | bc)")
[ -n "$rejected" ] && echo "check-clean: not judged, check rejects:$rejected"
if [ "$judged" = 0 ]; then
    echo "check-clean: no program passed check, so the row judged nothing" >&2
    exit 2
fi
summary="$judged judged: $built built, $known listed, $outside outside cause; $(wc -w <<< "$rejected") not judged; ${secs}s"
if [ "$fail" -ne 0 ]; then
    echo "check-clean: FAIL ($summary)"
    exit 1
fi
echo "check-clean: ok ($summary)"
[ -z "${CHECK_CLEAN_RESULT:-}" ] || echo "check-clean: ok ($summary)" > "$CHECK_CLEAN_RESULT"
