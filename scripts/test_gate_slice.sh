#!/bin/bash
# Proves scripts/install-gate-slice.sh: --dry-run prints the slice unit sized
# from the CPU count and the RAM and changes nothing, an install writes the
# unit and reloads the user manager once, a second install with the same
# values changes nothing, new values write it again, a reload that failed is
# done on the next run, a unit dir that the manager does not read fails the
# install, each drop-in that overrides the unit gets a warning, and a machine
# with no systemd or no user manager gets one line and exit 0. Also proves
# that a capped run with no slice unit prints one notice that names the
# install command, a nested run included.
# Every install goes to a mktemp XDG_CONFIG_HOME, with a fake systemctl on
# PATH, so the test never touches the real user manager.
set -u
cd "$(dirname "$0")/.."
INSTALL="$PWD/scripts/install-gate-slice.sh"
CAPPED="$PWD/scripts/capped.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0
pass() { echo "PASS: $1"; }
flunk() { echo "FAIL: $1"; fail=1; }

# The fake user manager: daemon-reload loads the unit from FAKE_MANAGER_DIR
# (else the installer's unit dir) into $WORK/loaded, and show reports it as
# systemd does. $WORK/nobus makes every call fail as with no user bus, and
# $WORK/fail-reload makes the next daemon-reload fail. $WORK/dropins holds
# the DropInPaths value. Each call goes to $WORK/systemctl.log.
mkdir -p "$WORK/mgr"
cat > "$WORK/mgr/systemctl" <<EOF
#!/bin/bash
W="$WORK"
echo "\$*" >> "\$W/systemctl.log"
if [ -e "\$W/nobus" ]; then
    echo "Failed to connect to user scope bus via local transport: No medium found" >&2
    exit 1
fi
src=\${FAKE_MANAGER_DIR:-\$XDG_CONFIG_HOME/systemd/user}/blink-gates.slice
case "\$*" in
    "--user show-environment") echo "HOME=\$HOME" ;;
    "--user daemon-reload")
        if [ -e "\$W/fail-reload" ]; then rm "\$W/fail-reload"; exit 1; fi
        rm -f "\$W/loaded" "\$W/loaded-from"
        if [ -f "\$src" ]; then cp "\$src" "\$W/loaded"; echo "\$src" > "\$W/loaded-from"; fi
        ;;
    "--user show -p FragmentPath -p NeedDaemonReload -p DropInPaths blink-gates.slice")
        from=\$(cat "\$W/loaded-from" 2>/dev/null)
        echo "FragmentPath=\$from"
        if [ -n "\$from" ] && ! cmp -s "\$from" "\$W/loaded"; then echo NeedDaemonReload=yes; else echo NeedDaemonReload=no; fi
        echo "DropInPaths=\$(cat "\$W/dropins" 2>/dev/null)"
        ;;
    *) echo "fake systemctl: unexpected call [\$*]" >&2; exit 1 ;;
esac
EOF
chmod +x "$WORK/mgr/systemctl"
: > "$WORK/systemctl.log"

# MemTotal as the kernel gives it: a little under the RAM size.
GIB=$((1024 * 1024))
ram64=$((61 * GIB + 700 * 1024))
ram16=$((15 * GIB + 500 * 1024))

# install <cpus> <memtotal KiB> [<arg>]: run the installer under the fakes.
install() {
    local cpus=$1 kib=$2
    shift 2
    env PATH="$WORK/mgr:$PATH" XDG_CONFIG_HOME="$WORK/cfg" \
        BLINK_SLICE_CPUS="$cpus" BLINK_SLICE_MEMTOTAL_KIB="$kib" "$INSTALL" "$@"
}
reloads() { grep -cx -- '--user daemon-reload' "$WORK/systemctl.log"; }

unit_file="$WORK/cfg/systemd/user/blink-gates.slice"

# key_set <text> <key=value>...: every line is in the text.
key_set() {
    local text=$1
    shift
    for kv in "$@"; do
        grep -qxF "$kv" <<<"$text" || return 1
    done
}

# --- --dry-run ---------------------------------------------------------------

out=$(install 24 "$ram64" --dry-run 2> "$WORK/err")
rc=$?
if [ "$rc" = 0 ] && key_set "$out" '[Slice]' CPUQuota=1200% MemoryHigh=15791M MemoryMax=23686M \
    MemorySwapMax=2G TasksMax=4096 ManagedOOMMemoryPressure=kill ManagedOOMSwap=kill; then
    pass "dry-run, 24 CPUs and 61.7 GiB: half the CPUs, a quarter and three eighths of the RAM"
else
    flunk "dry-run 24/61.7G (rc=$rc out=[$out] err=[$(cat "$WORK/err")])"
fi
if [ ! -e "$WORK/cfg" ] && [ ! -s "$WORK/systemctl.log" ]; then
    pass "dry-run writes no file and calls no systemctl"
else
    flunk "dry-run changed something (cfg: $(ls -R "$WORK/cfg" 2>&1 | tr '\n' ' '), systemctl: $(cat "$WORK/systemctl.log"))"
fi

out=$(install 8 "$ram16" --dry-run 2>/dev/null)
if key_set "$out" CPUQuota=400% MemoryHigh=3965M MemoryMax=5947M TasksMax=4096; then
    pass "dry-run, 8 CPUs and 15.5 GiB"
else
    flunk "dry-run 8/15.5G (out=[$out])"
fi

out=$(install 1 "$ram16" --dry-run 2>/dev/null)
if key_set "$out" CPUQuota=100%; then
    pass "dry-run, 1 CPU: the quota is never below one CPU"
else
    flunk "dry-run 1 CPU (out=[$out])"
fi

out=$(install 64 $((100 * GIB)) --dry-run 2>/dev/null)
if key_set "$out" CPUQuota=3200% MemoryHigh=25G MemoryMax=38400M; then
    pass "dry-run, 64 CPUs and 100 GiB: G for a whole GiB, else M"
else
    flunk "dry-run 64/100G (out=[$out])"
fi

out=$(install 2 $((1900 * 1024)) --dry-run 2>/dev/null)
if key_set "$out" MemoryHigh=475M MemoryMax=712M; then
    pass "dry-run, 1.9 GiB: the caps stay a fraction of the RAM"
else
    flunk "dry-run 1.9G (out=[$out])"
fi

for bad in --force x "--dry-run --dry-run"; do
    # shellcheck disable=SC2086
    if install 24 "$ram64" $bad > /dev/null 2>&1; then
        flunk "the installer accepted [$bad]"
    else
        pass "the installer refuses [$bad]"
    fi
done

# --- install, idempotent -------------------------------------------------------

dry=$(install 24 "$ram64" --dry-run 2>/dev/null)
out=$(install 24 "$ram64" 2>&1)
rc=$?
if [ "$rc" = 0 ] && [ -f "$unit_file" ] && [ "$(cat "$unit_file")" = "$dry" ] && [ "$(reloads)" = 1 ] &&
    grep -q 'MemoryMax=23686M' <<<"$out" && grep -q 'TasksMax=4096' <<<"$out"; then
    pass "install writes the dry-run unit, reloads once, and prints what it set"
else
    flunk "install (rc=$rc reloads=$(reloads) out=[$out] file=[$(cat "$unit_file" 2>&1)])"
fi

sum=$(cksum < "$unit_file")
out=$(install 24 "$ram64" 2>&1)
rc=$?
if [ "$rc" = 0 ] && [ "$(cksum < "$unit_file")" = "$sum" ] && [ "$(reloads)" = 1 ] && grep -q 'up to date' <<<"$out"; then
    pass "a second install with the same values changes nothing and does not reload"
else
    flunk "second install (rc=$rc reloads=$(reloads) out=[$out])"
fi

out=$(install 8 "$ram16" 2>&1)
rc=$?
if [ "$rc" = 0 ] && grep -qx 'CPUQuota=400%' "$unit_file" && [ "$(reloads)" = 2 ]; then
    pass "an install with new values writes the unit again and reloads"
else
    flunk "install with new values (rc=$rc reloads=$(reloads) out=[$out])"
fi

# A failed reload leaves the new file on disk; the next run must still
# reload, not call the unit up to date.
touch "$WORK/fail-reload"
install 24 "$ram64" > "$WORK/out" 2>&1
rc1=$?
out=$(install 24 "$ram64" 2>&1)
rc2=$?
if [ "$rc1" != 0 ] && [ "$rc2" = 0 ] && [ "$(reloads)" = 4 ] && cmp -s "$unit_file" "$WORK/loaded" &&
    ! grep -q 'up to date' <<<"$out"; then
    pass "a failed reload fails the run, and the next run reloads"
else
    flunk "failed reload (rc1=$rc1 rc2=$rc2 reloads=$(reloads) first=[$(cat "$WORK/out")] second=[$out])"
fi

# The manager reads another unit dir, as when the shell and the manager
# have a different XDG_CONFIG_HOME.
out=$(env FAKE_MANAGER_DIR="$WORK/elsewhere" PATH="$WORK/mgr:$PATH" XDG_CONFIG_HOME="$WORK/cfg2" \
    BLINK_SLICE_CPUS=24 BLINK_SLICE_MEMTOTAL_KIB="$ram64" "$INSTALL" 2>&1)
rc=$?
if [ "$rc" != 0 ] && grep -qF "$WORK/cfg2/systemd/user/blink-gates.slice" <<<"$out" && grep -q 'XDG_CONFIG_HOME' <<<"$out"; then
    pass "a unit dir that the manager does not read fails the install and names the dir"
else
    flunk "manager reads another dir (rc=$rc out=[$out])"
fi
install 24 "$ram64" > /dev/null 2>&1

if ! grep -v -x -e '--user daemon-reload' -e '--user show-environment' \
    -e '--user show -p FragmentPath -p NeedDaemonReload -p DropInPaths blink-gates.slice' \
    "$WORK/systemctl.log" | grep -q .; then
    pass "the installer only reads the manager and reloads it"
else
    flunk "the installer made other systemctl calls: $(sort -u "$WORK/systemctl.log")"
fi

# --- drop-ins ------------------------------------------------------------------------

d1="$WORK/cfg/systemd/user.control/blink-gates.slice.d/50-MemoryHigh.conf"
d2="/run/user/0/systemd/user.control/blink-gates.slice.d/50-TasksMax.conf"
echo "$d1 $d2" > "$WORK/dropins"
out=$(install 24 "$ram64" 2>&1)
rc=$?
if [ "$rc" = 0 ] && grep -qF "  $d1" <<<"$out" && grep -qF "  $d2" <<<"$out" &&
    grep -qF 'systemctl --user revert blink-gates.slice' <<<"$out"; then
    pass "drop-ins get a warning that names each file and the command that removes them"
else
    flunk "drop-in warning (rc=$rc out=[$out])"
fi
rm "$WORK/dropins"
out=$(install 24 "$ram64" 2>&1)
rc=$?
if [ "$rc" = 0 ] && ! grep -q 'drop-in' <<<"$out"; then
    pass "no drop-ins, no warning"
else
    flunk "warning with no drop-ins (rc=$rc out=[$out])"
fi

# --- no systemd ---------------------------------------------------------------------

touch "$WORK/nobus"
out=$(env PATH="$WORK/mgr:$PATH" XDG_CONFIG_HOME="$WORK/cfg-nobus" BLINK_SLICE_CPUS=24 \
    BLINK_SLICE_MEMTOTAL_KIB="$ram64" "$INSTALL" 2>&1)
rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" = 0 ] && [ "$lines" = 1 ] && [ ! -e "$WORK/cfg-nobus" ]; then
    pass "no user manager: one line, exit 0, nothing written"
else
    flunk "no user manager (rc=$rc out=[$out])"
fi
out=$(env PATH="$WORK/mgr:$PATH" XDG_CONFIG_HOME="$WORK/cfg-nobus" BLINK_SLICE_CPUS=24 \
    BLINK_SLICE_MEMTOTAL_KIB="$ram64" "$INSTALL" --dry-run 2>&1)
rc=$?
if [ "$rc" = 0 ] && grep -qx 'CPUQuota=1200%' <<<"$out"; then
    pass "no user manager, --dry-run: still prints the unit"
else
    flunk "no user manager, --dry-run (rc=$rc out=[$out])"
fi
rm "$WORK/nobus"

nosd="$WORK/nosd"
mkdir -p "$nosd"
for t in bash env cat dirname uname nproc mkdir mv sed; do
    p=$(command -v "$t") && ln -sf "$p" "$nosd/$t"
done
for args in "" --dry-run; do
    out=$(env PATH="$nosd" XDG_CONFIG_HOME="$WORK/cfg-nosd" "$INSTALL" $args 2>&1)
    rc=$?
    lines=$(printf '%s\n' "$out" | grep -c .)
    if [ "$rc" = 0 ] && [ "$lines" = 1 ] && [ ! -e "$WORK/cfg-nosd" ]; then
        pass "no systemctl ($args): one line, exit 0, nothing written"
    else
        flunk "no systemctl ($args) (rc=$rc out=[$out])"
    fi
done

darwin="$WORK/darwin"
mkdir -p "$darwin"
printf '#!/bin/sh\necho Darwin\n' > "$darwin/uname"
chmod +x "$darwin/uname"
out=$(env PATH="$darwin:$WORK/mgr:$PATH" XDG_CONFIG_HOME="$WORK/cfg-darwin" "$INSTALL" 2>&1)
rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" = 0 ] && [ "$lines" = 1 ] && [ ! -e "$WORK/cfg-darwin" ]; then
    pass "Darwin: one line, exit 0, nothing written"
else
    flunk "Darwin (rc=$rc out=[$out])"
fi

# --- capped.sh notice ---------------------------------------------------------------

# Each case runs as a fresh top-level gate, with a fake systemctl whose
# `show` prints nothing, as for a slice with no unit; the real systemd-run
# still makes the scope.
mkdir -p "$WORK/nounit"
printf '#!/bin/sh\nexit 0\n' > "$WORK/nounit/systemctl"
chmod +x "$WORK/nounit/systemctl"
if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope -q true >/dev/null 2>&1; then
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP -u BLINK_GATE_SLICE PATH="$WORK/nounit:$PATH" \
        "$CAPPED" bash -c "\"$CAPPED\" true" 2> "$WORK/err"
    rc=$?
    hits=$(grep -c 'scripts/install-gate-slice.sh' "$WORK/err")
    if [ "$rc" = 0 ] && [ "$hits" = 1 ] && grep -q '^capped.sh: blink-gates.slice has no unit' "$WORK/err"; then
        pass "a capped run with no slice unit prints one notice with the install command, nested run included"
    else
        flunk "missing-slice notice (rc=$rc hits=$hits err=[$(cat "$WORK/err")])"
    fi
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP PATH="$WORK/nounit:$PATH" \
        BLINK_GATE_SLICE=blink-gates-selftest-no-unit.slice "$CAPPED" true 2> "$WORK/err"
    rc=$?
    if [ "$rc" = 0 ] && grep -q '^capped.sh: blink-gates-selftest-no-unit.slice has no unit' "$WORK/err" &&
        ! grep -q 'install-gate-slice' "$WORK/err"; then
        pass "a slice other than blink-gates.slice gets the notice with no install hint"
    else
        flunk "notice for another slice (rc=$rc err=[$(cat "$WORK/err")])"
    fi
else
    echo "SKIP: no systemd user scope here; the capped.sh notice cases did not run"
fi

if [ $fail -ne 0 ]; then echo "test_gate_slice: FAILED"; exit 1; fi
echo "test_gate_slice: all passed"
