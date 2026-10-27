#!/bin/bash
# Proves scripts/install-gate-slice.sh: --dry-run prints the slice unit sized
# from the CPU count and the RAM and changes nothing, an install writes the
# unit and reloads the user manager once, a second install with the same
# values changes nothing, new values write it again, set-property drop-ins
# that would override the unit get a warning, and a machine with no systemd
# gets one line and exit 0. Also proves that a capped run with no slice unit
# prints one notice that names the install command, a nested run included.
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

# The fake systemctl logs each call, and `show` prints nothing, as for a
# slice with no unit and no drop-in.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/systemctl" <<EOF
#!/bin/bash
echo "\$*" >> "$WORK/systemctl.log"
EOF
chmod +x "$WORK/bin/systemctl"
: > "$WORK/systemctl.log"

# MemTotal as the kernel gives it: a little under the RAM size.
GIB=$((1024 * 1024))
ram64=$((61 * GIB + 700 * 1024))
ram16=$((15 * GIB + 500 * 1024))

# install <cpus> <memtotal KiB> [<arg>]: run the installer under the fakes.
install() {
    local cpus=$1 kib=$2
    shift 2
    env PATH="$WORK/bin:$PATH" XDG_CONFIG_HOME="$WORK/cfg" \
        BLINK_SLICE_CPUS="$cpus" BLINK_SLICE_MEMTOTAL_KIB="$kib" "$INSTALL" "$@"
}

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
if [ "$rc" = 0 ] && key_set "$out" '[Slice]' CPUQuota=1200% MemoryHigh=16G MemoryMax=24G \
    MemorySwapMax=2G TasksMax=4096 ManagedOOMMemoryPressure=kill ManagedOOMSwap=kill; then
    pass "dry-run, 24 CPUs and 64G: the budget's slice values"
else
    flunk "dry-run 24/64G (rc=$rc out=[$out] err=[$(cat "$WORK/err")])"
fi
if [ ! -e "$WORK/cfg" ] && [ ! -s "$WORK/systemctl.log" ]; then
    pass "dry-run writes no file and calls no systemctl"
else
    flunk "dry-run changed something (cfg: $(ls -R "$WORK/cfg" 2>&1 | tr '\n' ' '), systemctl: $(cat "$WORK/systemctl.log"))"
fi

out=$(install 8 "$ram16" --dry-run 2>/dev/null)
if key_set "$out" CPUQuota=400% MemoryHigh=4G MemoryMax=6G TasksMax=4096; then
    pass "dry-run, 8 CPUs and 16G: half the CPUs, a quarter and three eighths of the RAM"
else
    flunk "dry-run 8/16G (out=[$out])"
fi

out=$(install 1 "$ram16" --dry-run 2>/dev/null)
if key_set "$out" CPUQuota=100%; then
    pass "dry-run, 1 CPU: the quota is never below one CPU"
else
    flunk "dry-run 1 CPU (out=[$out])"
fi

# Unrounded RAM: 61.7 GiB rounds up to 64, not down to 56.
out=$(install 64 $((100 * GIB)) --dry-run 2>/dev/null)
if key_set "$out" CPUQuota=3200% MemoryHigh=26G MemoryMax=39G; then
    pass "dry-run, 64 CPUs and 100G: RAM rounds up to a multiple of 8G (104G)"
else
    flunk "dry-run 64/100G (out=[$out])"
fi

for bad in --force x; do
    if install 24 "$ram64" "$bad" > /dev/null 2>&1; then
        flunk "the installer accepted [$bad]"
    else
        pass "the installer refuses [$bad]"
    fi
done

# --- install, idempotent -------------------------------------------------------

dry=$(install 24 "$ram64" --dry-run 2>/dev/null)
out=$(install 24 "$ram64" 2>&1)
rc=$?
reloads=$(grep -cx -- '--user daemon-reload' "$WORK/systemctl.log")
if [ "$rc" = 0 ] && [ -f "$unit_file" ] && [ "$(cat "$unit_file")" = "$dry" ] && [ "$reloads" = 1 ] &&
    grep -q 'MemoryMax=24G' <<<"$out"; then
    pass "install writes the dry-run unit, reloads once, and prints what it set"
else
    flunk "install (rc=$rc reloads=$reloads out=[$out] file=[$(cat "$unit_file" 2>&1)])"
fi

sum=$(cksum < "$unit_file")
out=$(install 24 "$ram64" 2>&1)
rc=$?
reloads=$(grep -cx -- '--user daemon-reload' "$WORK/systemctl.log")
if [ "$rc" = 0 ] && [ "$(cksum < "$unit_file")" = "$sum" ] && [ "$reloads" = 1 ]; then
    pass "a second install with the same values changes nothing and does not reload"
else
    flunk "second install (rc=$rc reloads=$reloads out=[$out])"
fi

out=$(install 8 "$ram16" 2>&1)
reloads=$(grep -cx -- '--user daemon-reload' "$WORK/systemctl.log")
if grep -qx 'CPUQuota=400%' "$unit_file" && [ "$reloads" = 2 ]; then
    pass "an install with new values writes the unit again and reloads"
else
    flunk "install with new values (reloads=$reloads out=[$out])"
fi

if ! grep -v -e '^--user daemon-reload$' "$WORK/systemctl.log" | grep -q .; then
    pass "the installer calls systemctl for daemon-reload only"
else
    flunk "the installer made other systemctl calls: $(cat "$WORK/systemctl.log")"
fi

# --- drop-ins from systemctl set-property ------------------------------------------

dropins="$WORK/cfg/systemd/user.control/blink-gates.slice.d"
mkdir -p "$dropins"
printf '[Slice]\nMemoryHigh=21474836480\n' > "$dropins/50-MemoryHigh.conf"
out=$(install 24 "$ram64" 2>&1)
rc=$?
if [ "$rc" = 0 ] && grep -qF "$dropins/50-MemoryHigh.conf" <<<"$out" && grep -qF "rm -r $dropins" <<<"$out"; then
    pass "set-property drop-ins get a warning that names each file and the command to remove them"
else
    flunk "drop-in warning (rc=$rc out=[$out])"
fi
rm -r "$WORK/cfg/systemd/user.control"
out=$(install 24 "$ram64" 2>&1)
rc=$?
if [ "$rc" = 0 ] && ! grep -q 'user.control' <<<"$out"; then
    pass "no drop-ins, no warning"
else
    flunk "warning with no drop-ins (rc=$rc out=[$out])"
fi

# --- no systemd ---------------------------------------------------------------------

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
out=$(env PATH="$darwin:$WORK/bin:$PATH" XDG_CONFIG_HOME="$WORK/cfg-darwin" "$INSTALL" 2>&1)
rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" = 0 ] && [ "$lines" = 1 ] && [ ! -e "$WORK/cfg-darwin" ]; then
    pass "Darwin: one line, exit 0, nothing written"
else
    flunk "Darwin (rc=$rc out=[$out])"
fi

# --- capped.sh notice ---------------------------------------------------------------

# Runs as a fresh top-level gate, with the fake systemctl saying that the
# slice has no unit; the real systemd-run still makes the scope.
if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope -q true >/dev/null 2>&1; then
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP -u BLINK_GATE_SLICE PATH="$WORK/bin:$PATH" \
        "$CAPPED" bash -c "\"$CAPPED\" true" 2> "$WORK/err"
    rc=$?
    hits=$(grep -c 'scripts/install-gate-slice.sh' "$WORK/err")
    if [ "$rc" = 0 ] && [ "$hits" = 1 ] && grep -q '^capped.sh: blink-gates.slice has no unit' "$WORK/err"; then
        pass "a capped run with no slice unit prints one notice with the install command, nested run included"
    else
        flunk "missing-slice notice (rc=$rc hits=$hits err=[$(cat "$WORK/err")])"
    fi
    env -u BLINK_GATE_SCOPE -u BLINK_GATE_CAP PATH="$WORK/bin:$PATH" \
        BLINK_GATE_SLICE=blink-gates-selftest-no-unit.slice "$CAPPED" true 2> "$WORK/err"
    if ! grep -q 'install-gate-slice' "$WORK/err"; then
        pass "a slice other than blink-gates.slice gets no install hint"
    else
        flunk "install hint for another slice (err=[$(cat "$WORK/err")])"
    fi
else
    echo "SKIP: no systemd user scope here; the capped.sh notice cases did not run"
fi

if [ $fail -ne 0 ]; then echo "test_gate_slice: FAILED"; exit 1; fi
echo "test_gate_slice: all passed"
