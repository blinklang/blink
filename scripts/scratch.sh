#!/bin/bash
# One home for probe and fixture builds, so they are easy to find, measure and
# remove. On 2026-10-27 probe builds left in a session scratchpad reached 21G on
# a tmpfs /tmp, which is RAM. See docs/build/gate-memory-budget.md.
#
#   scripts/scratch.sh new <name>      make <root>/<name>, print its path
#   scripts/scratch.sh clean <name>    remove <root>/<name>
#   scripts/scratch.sh clean --all     remove the root
#   scripts/scratch.sh check           print each dir's size; warn past the limit
#
# Root: BLINK_SCRATCH_ROOT, else ${TMPDIR:-/tmp}/blink-probe-<user>. Its last
# part must be blink-probe-<user>, so a bad value cannot point clean at / or
# $HOME or any other dir.
# BLINK_SCRATCH_WARN (default 4G) is the total past which check warns.
# check always exits 0: it runs at the end of `task ci` and must not fail it.
set -u

die() { echo "scratch.sh: $*" >&2; exit 2; }

user=$(id -un)
root=${BLINK_SCRATCH_ROOT:-${TMPDIR:-/tmp}/blink-probe-$user}
root=${root%/}

# The root with each symlink in its parent resolved and each // folded, so
# the $HOME test below compares paths, not spellings. Fails when the parent
# is not a dir.
canon_root() {
    local parent
    parent=$(cd -P -- "${root%/*}/" 2>/dev/null && pwd -P) || return 1
    echo "${parent%/}/${root##*/}"
}

# Empty when the root is safe, else why not.
root_problem() {
    case "$root" in
        /*) ;;
        *) echo "root '$root' is not an absolute path"; return ;;
    esac
    case "${root##*/}" in
        "blink-probe-$user") ;;
        *) echo "root '$root' is not named blink-probe-$user"; return ;;
    esac
    case "$root" in
        *//*) echo "root '$root' holds //"; return ;;
    esac
    case "/$root/" in
        */../*|*/./*) echo "root '$root' holds . or .."; return ;;
    esac
    local r h
    r=$(canon_root) || { echo "root '$root' has no parent dir"; return; }
    [ -L "$r" ] && { echo "root '$root' is a symlink"; return; }
    if [ -e "$r" ] && [ ! -d "$r" ]; then echo "root '$root' is not a dir"; return; fi
    # In a shared /tmp another user could make the root first.
    if [ -e "$r" ] && [ ! -O "$r" ]; then echo "root '$root' is not yours"; return; fi
    # A $HOME that does not exist cannot be lost.
    h=$(cd -P -- "${HOME:-/nonexistent}" 2>/dev/null && pwd -P) || return 0
    case "${h%/}/" in
        "$r"/*) echo "root '$root' holds \$HOME"; return ;;
    esac
}

check_name() {
    case "$1" in
        ''|.*|-*|*/*) die "bad name '$1'" ;;
    esac
}

# kib <size>: KiB of a size in K, M, G or T; nothing for a bad size.
kib() {
    local u=${1^^}
    local n=${u%[KMGT]}
    case "$n" in ''|*[!0-9]*) return ;; esac
    n=$((10#$n))
    case "$u" in
        *K) echo "$n" ;;
        *M) echo $((n * 1024)) ;;
        *G) echo $((n * 1024 * 1024)) ;;
        *T) echo $((n * 1024 * 1024 * 1024)) ;;
        *) echo $(((n + 1023) / 1024)) ;;
    esac
}

human() {
    local k=$1
    if [ "$k" -ge 1048576 ]; then echo "$((k / 1048576))G"
    elif [ "$k" -ge 1024 ]; then echo "$((k / 1024))M"
    else echo "${k}K"; fi
}

cmd=${1:-}
case "$cmd" in
    new|clean)
        # A check that fails without a reason must still refuse.
        why=$(root_problem) || why="root check failed on '$root'"
        [ -z "$why" ] || die "refused: $why"
        root=$(canon_root) || die "refused: root '$root' has no parent dir"
        ;;
    check)
        why=$(root_problem) || why="root check failed on '$root'"
        [ -z "$why" ] || { echo "scratch.sh: warning: $why; not checked"; exit 0; }
        root=$(canon_root) || exit 0
        ;;
    *) die "usage: scratch.sh new <name> | clean <name> | clean --all | check" ;;
esac

case "$cmd" in
    new)
        [ $# -eq 2 ] || die "usage: scratch.sh new <name>"
        check_name "$2"
        mkdir -p -m 700 "$root" || exit 1
        mkdir -p "$root/$2" || exit 1
        echo "$root/$2"
        ;;
    clean)
        [ $# -eq 2 ] || die "usage: scratch.sh clean <name> | clean --all"
        # rm -rf removes a symlink, never what it points to.
        if [ "$2" = --all ]; then
            rm -rf -- "$root"
        else
            check_name "$2"
            rm -rf -- "${root:?}/$2"
        fi
        ;;
    check)
        [ -d "$root" ] || exit 0
        limit=${BLINK_SCRATCH_WARN:-4G}
        limit_k=$(kib "$limit")
        [ -n "$limit_k" ] || { echo "scratch.sh: warning: BLINK_SCRATCH_WARN='$limit' is not a size; using 4G"; limit=4G; limit_k=$(kib 4G); }
        total=0
        for d in "$root"/* "$root"/.[!.]* "$root"/..?*; do
            [ -e "$d" ] || [ -L "$d" ] || continue
            k=$(du -sk -- "$d" 2>/dev/null | cut -f1)
            k=${k:-0}
            total=$((total + k))
            echo "scratch: $(human "$k") $d"
        done
        fs=$(stat -f -c %T "$root" 2>/dev/null)
        note=""
        [ "$fs" = tmpfs ] && note=" (on tmpfs, so it is RAM)"
        echo "scratch: $(human "$total") total in $root$note"
        if [ "$total" -gt "$limit_k" ]; then
            echo "scratch.sh: warning: $(human "$total") of probes past $limit$note; run scripts/scratch.sh clean <name> or clean --all"
        fi
        ;;
esac
exit 0
