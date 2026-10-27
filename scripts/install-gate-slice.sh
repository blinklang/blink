#!/bin/bash
# Install blink-gates.slice as a systemd user unit, sized for this machine.
# scripts/capped.sh puts each gate run's scope in this slice, so its limits
# hold over all gates at once. See docs/build/gate-memory-budget.md.
#
#   scripts/install-gate-slice.sh [--dry-run]
#
# --dry-run prints the unit and changes nothing. Without it, the script writes
# the unit to ${XDG_CONFIG_HOME:-~/.config}/systemd/user and reloads the user
# manager, but only when the unit changed. No sudo.
#
# Env (for tests, or to size the slice for another machine):
#   BLINK_SLICE_CPUS          CPU count (default: nproc --all)
#   BLINK_SLICE_MEMTOTAL_KIB  RAM in KiB (default: MemTotal in /proc/meminfo)
set -u
cd "$(dirname "$0")/.."

dry=0
case "${1:-}" in
    '') ;;
    --dry-run) dry=1 ;;
    *) echo "usage: scripts/install-gate-slice.sh [--dry-run]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "usage: scripts/install-gate-slice.sh [--dry-run]" >&2; exit 2; }

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
# MemTotal is a little under the RAM size (61.7 GiB on a 64G machine), so
# round it up to a multiple of 8 GiB before the fractions.
gib=$(( (kib + 8 * 1024 * 1024 - 1) / (8 * 1024 * 1024) * 8 ))
high=$((gib / 4))G
max=$((gib * 3 / 8))G

unit=$(sed -e "s/@CPU_QUOTA@/$quota/" -e "s/@MEMORY_HIGH@/$high/" -e "s/@MEMORY_MAX@/$max/" \
    scripts/systemd/blink-gates.slice) || exit 1

if [ "$dry" = 1 ]; then
    printf '%s\n' "$unit"
    exit 0
fi

config=${XDG_CONFIG_HOME:-$HOME/.config}
dir=$config/systemd/user
file=$dir/blink-gates.slice
set_values="CPUQuota=$quota MemoryHigh=$high MemoryMax=$max MemorySwapMax=2G TasksMax=4096"
if [ -f "$file" ] && [ "$(cat "$file")" = "$unit" ]; then
    echo "install-gate-slice.sh: $file is up to date: $set_values"
else
    mkdir -p "$dir" || exit 1
    printf '%s\n' "$unit" > "$file.tmp" && mv "$file.tmp" "$file" || exit 1
    systemctl --user daemon-reload || exit 1
    echo "install-gate-slice.sh: wrote $file and reloaded the user manager: $set_values"
fi

# systemctl set-property writes drop-ins here, and they override the unit.
control=$config/systemd/user.control/blink-gates.slice.d
found=()
for f in "$control"/*.conf; do
    [ -e "$f" ] && found+=("$f")
done
if [ ${#found[@]} -gt 0 ]; then
    echo "install-gate-slice.sh: these drop-ins from systemctl set-property override the unit:"
    printf '  %s\n' "${found[@]}"
    echo "install-gate-slice.sh: to use the unit's values, run: rm -r $control && systemctl --user daemon-reload"
fi
