#!/bin/bash
# Install blink-gates.slice as a systemd user unit, sized for this machine.
# scripts/capped.sh puts each gate run's scope in this slice, so its limits
# hold over all gates at once. See docs/build/gate-memory-budget.md.
#
#   scripts/install-gate-slice.sh [--dry-run]
#
# --dry-run prints the unit and changes nothing. Without it, the script writes
# the unit to ${XDG_CONFIG_HOME:-~/.config}/systemd/user and reloads the user
# manager when the unit changed or the manager has not loaded it. No sudo.
#
# Env (for tests, or to size the slice for another machine):
#   BLINK_SLICE_CPUS          CPU count (default: nproc --all)
#   BLINK_SLICE_MEMTOTAL_KIB  RAM in KiB (default: MemTotal in /proc/meminfo)
set -u
cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/install-gate-slice.sh [--dry-run]" >&2; exit 2; }
dry=0
[ $# -le 1 ] || usage
case "${1:-}" in
    '') ;;
    --dry-run) dry=1 ;;
    *) usage ;;
esac

if [ "$(uname -s 2>/dev/null)" != Linux ] || ! command -v systemctl >/dev/null 2>&1; then
    echo "install-gate-slice.sh: no systemd on this machine, so there is no slice to install; scripts/capped.sh caps each run on its own"
    exit 0
fi

# All CPUs, not the bare nproc: inside the slice, nproc gives the quota.
cpus=${BLINK_SLICE_CPUS:-$(nproc --all)}
kib=${BLINK_SLICE_MEMTOTAL_KIB:-}
if [ -z "$kib" ]; then
    while read -r k v _; do
        [ "$k" = MemTotal: ] && { kib=$v; break; }
    done < /proc/meminfo
fi
case "$cpus" in '' | *[!0-9]* | 0) echo "install-gate-slice.sh: bad CPU count [$cpus]" >&2; exit 1 ;; esac
case "$kib" in '' | *[!0-9]* | 0) echo "install-gate-slice.sh: bad RAM size [$kib KiB]" >&2; exit 1 ;; esac

# Half the CPUs, as scripts/default_jobs.sh gives a gate outside the slice.
half=$((cpus / 2))
[ "$half" -ge 1 ] || half=1
quota=$((half * 100))%
# size <MiB>: in G when it is a whole number of GiB, else in M.
size() { if [ $(($1 % 1024)) = 0 ]; then echo "$(($1 / 1024))G"; else echo "${1}M"; fi; }
mib=$((kib / 1024))
high=$(size $((mib / 4)))
max=$(size $((mib * 3 / 8)))

unit=$(sed -e "s/@CPU_QUOTA@/$quota/" -e "s/@MEMORY_HIGH@/$high/" -e "s/@MEMORY_MAX@/$max/" \
    scripts/systemd/blink-gates.slice) || exit 1

if [ "$dry" = 1 ]; then
    printf '%s\n' "$unit"
    exit 0
fi

if ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "install-gate-slice.sh: no systemd user manager in this session, so nothing was installed; scripts/capped.sh caps each run on its own"
    exit 0
fi

config=${XDG_CONFIG_HOME:-$HOME/.config}
dir=$config/systemd/user
file=$dir/blink-gates.slice
set_values=$(sed -n '/^\[Slice\]/,$s/^\([A-Za-z]*=.*\)/\1/p' <<<"$unit" | tr '\n' ' ')

# show [<key>]: the manager's view of the slice, or one key from it.
show() {
    systemctl --user show -p FragmentPath -p NeedDaemonReload -p DropInPaths blink-gates.slice |
        sed -n "s/^$1=//p"
}

changed=0
if ! [ -f "$file" ] || [ "$(cat "$file")" != "$unit" ]; then
    mkdir -p "$dir" || exit 1
    printf '%s\n' "$unit" > "$file.tmp" && mv "$file.tmp" "$file" || exit 1
    changed=1
fi
# A reload that failed on an earlier run leaves the file new on disk but
# not loaded, so look at the manager too, not only at the file.
if [ "$changed" = 1 ] || [ "$(show NeedDaemonReload)" = yes ] || [ "$(show FragmentPath)" != "$file" ]; then
    systemctl --user daemon-reload || { echo "install-gate-slice.sh: wrote $file, but the user manager did not reload; run the script again" >&2; exit 1; }
    if [ "$(show FragmentPath)" != "$file" ]; then
        echo "install-gate-slice.sh: wrote $file, but the user manager does not read it; the manager may have another XDG_CONFIG_HOME than this shell" >&2
        exit 1
    fi
    echo "install-gate-slice.sh: wrote $file and reloaded the user manager: ${set_values% }"
else
    echo "install-gate-slice.sh: $file is up to date: ${set_values% }"
fi

# systemctl set-property and other drop-ins override the unit.
read -r -a found <<<"$(show DropInPaths)"
if [ ${#found[@]} -gt 0 ]; then
    echo "install-gate-slice.sh: these drop-ins override the unit:"
    printf '  %s\n' "${found[@]}"
    echo "install-gate-slice.sh: to use the unit's values, run: systemctl --user revert blink-gates.slice"
fi
