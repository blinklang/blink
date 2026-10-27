#!/bin/bash
# Proves scripts/scratch.sh: `new` makes a probe dir under one root and prints
# its path, `clean` removes one dir or all of them and no symlink target,
# `check` prints each dir's size, names a tmpfs root, warns past the limit and
# exits 0 even then, and every command refuses a root that is "/", holds
# $HOME by any spelling, holds //, is a symlink, or is not named
# blink-probe-<user>. Each
# root that clean may touch is under a mktemp dir; "/" and the real $HOME get
# only new and check.
set -u
cd "$(dirname "$0")/.."
SCRATCH="$PWD/scripts/scratch.sh"

WORK=$(mktemp -d)
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
fail=0
pass() { echo "PASS: $1"; }
flunk() { echo "FAIL: $1"; fail=1; }

run() { env -u BLINK_SCRATCH_ROOT -u BLINK_SCRATCH_WARN TMPDIR="$WORK/tmp" "$@"; }
mkdir -p "$WORK/tmp"
user=$(id -un)
P=blink-probe-$user
root="$WORK/tmp/$P"

# new: default root under TMPDIR, path on stdout
p=$(run "$SCRATCH" new probe1)
if [ "$p" = "$root/probe1" ] && [ -d "$p" ]; then pass "new makes the dir under TMPDIR"; else flunk "new printed '$p'"; fi
p2=$(run "$SCRATCH" new probe1)
[ "$p2" = "$p" ] && pass "new on an existing dir prints its path" || flunk "second new printed '$p2'"
for bad in '' . .. a/b ../x '-x' .hidden ..big; do
    if run "$SCRATCH" new "$bad" >/dev/null 2>&1; then flunk "new accepted name '$bad'"; else pass "new refuses name '$bad'"; fi
done

# check: sizes, no warning under the limit, warning past it, exit 0
dd if=/dev/zero of="$p/fill" bs=1024 count=10240 status=none
run "$SCRATCH" new probe2 >/dev/null
out=$(run "$SCRATCH" check 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'probe1' <<<"$out" && grep -q 'probe2' <<<"$out" && ! grep -qi 'warning' <<<"$out"; then
    pass "check lists each dir and no warning under the limit"
else flunk "check under the limit: rc=$rc out=$out"; fi
out=$(run env BLINK_SCRATCH_WARN=16K "$SCRATCH" check 2>&1); rc=$?
if [ $rc -eq 0 ] && [ "$(grep -ci 'warning' <<<"$out")" -eq 1 ]; then
    pass "check warns in one line past the limit and exits 0"
else flunk "check over the limit: rc=$rc out=$out"; fi
out=$(run env BLINK_SCRATCH_WARN=junk "$SCRATCH" check 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "not a size; using 4G" <<<"$out"; then
    pass "check falls back to 4G on a bad limit and exits 0"
else flunk "check bad limit: rc=$rc out=$out"; fi
# A leading zero is base 10, not octal: the 10M here is past 09M and not past 011M.
out=$(run env BLINK_SCRATCH_WARN=09M "$SCRATCH" check 2>&1)
if grep -q 'warning: .* past 09M' <<<"$out"; then pass "09M reads as 9M"; else flunk "09M: $out"; fi
out=$(run env BLINK_SCRATCH_WARN=011M "$SCRATCH" check 2>&1)
if ! grep -qi warning <<<"$out"; then pass "011M reads as 11M"; else flunk "011M: $out"; fi
# Each entry counts, also one named ..x
mkdir "$root/..big"
dd if=/dev/zero of="$root/..big/fill" bs=1024 count=10240 status=none
out=$(run env BLINK_SCRATCH_WARN=15M "$SCRATCH" check 2>&1)
if grep -q '\.\.big' <<<"$out" && grep -q 'warning' <<<"$out"; then pass "check counts an entry named ..x"; else flunk "..big: $out"; fi
rm -rf "$root/..big"

# check: names tmpfs, by a fake stat that says the root is on tmpfs
mkdir -p "$WORK/bin"
cat > "$WORK/bin/stat" <<EOF
#!/bin/sh
[ "\$1" = -f ] && { echo tmpfs; exit 0; }
exec $(command -v stat) "\$@"
EOF
chmod +x "$WORK/bin/stat"
out=$(run env PATH="$WORK/bin:$PATH" "$SCRATCH" check 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -qi 'tmpfs' <<<"$out"; then pass "check says the root is on tmpfs"; else flunk "tmpfs: rc=$rc out=$out"; fi
out=$(run "$SCRATCH" check 2>&1)
if [ "$(stat -f -c %T "$root" 2>/dev/null)" != tmpfs ] && grep -qi 'tmpfs' <<<"$out"; then
    flunk "check names tmpfs on a root that is not on tmpfs"
else pass "check names tmpfs only on tmpfs"; fi

# clean <name>
run "$SCRATCH" clean probe1 && [ ! -e "$root/probe1" ] && [ -d "$root/probe2" ] \
    && pass "clean removes one dir" || flunk "clean probe1"
run "$SCRATCH" clean nothere && pass "clean of a missing dir exits 0" || flunk "clean nothere"
if run "$SCRATCH" clean ../x >/dev/null 2>&1; then flunk "clean accepted ../x"; else pass "clean refuses ../x"; fi

# clean does not follow a symlink out of the root
mkdir -p "$WORK/outside/keep"; touch "$WORK/outside/keep/f"
ln -s "$WORK/outside/keep" "$root/link"
run "$SCRATCH" new probe3 >/dev/null
ln -s "$WORK/outside" "$root/probe3/inner"
run "$SCRATCH" clean link
run "$SCRATCH" clean probe3
if [ -f "$WORK/outside/keep/f" ] && [ ! -e "$root/link" ] && [ ! -e "$root/probe3" ]; then
    pass "clean removes a symlink, not its target"
else flunk "clean followed a symlink"; fi

# clean --all
run "$SCRATCH" new probe4 >/dev/null
run "$SCRATCH" clean --all && [ ! -e "$root" ] && pass "clean --all removes the root" || flunk "clean --all"
run "$SCRATCH" clean --all && pass "clean --all with no root exits 0" || flunk "clean --all twice"
out=$(run "$SCRATCH" check 2>&1); rc=$?
[ $rc -eq 0 ] && pass "check with no root exits 0" || flunk "check no root rc=$rc"

# hostile roots. Each row names the reason it must give, so a refusal by an
# earlier guard cannot pass it. new and check run on the real / and $HOME;
# clean runs only on roots under $WORK.
# refused <expect reason> <env...>: new and clean --all refuse with the
# reason; check exits 0 with the reason and measures nothing.
refused() {
    local reason=$1; shift
    local label="$*"
    out=$(run env "$@" "$SCRATCH" new z 2>&1)
    if [ $? -ne 0 ] && grep -q "$reason" <<<"$out"; then pass "new refuses: $label"; else flunk "new on $label: $out"; fi
    out=$(run env "$@" "$SCRATCH" clean --all 2>&1)
    if [ $? -ne 0 ] && grep -q "$reason" <<<"$out"; then pass "clean --all refuses: $label"; else flunk "clean --all on $label: $out"; fi
    out=$(run env "$@" "$SCRATCH" check 2>&1); rc=$?
    if [ $rc -eq 0 ] && grep -q "$reason.*not checked" <<<"$out" && ! grep -q '^scratch:' <<<"$out"; then
        pass "check skips: $label"
    else flunk "check on $label: rc=$rc $out"; fi
}
# Only new and check, so a broken guard cannot remove a real dir.
refused_safe() {
    local reason=$1; shift
    out=$(run env "$@" "$SCRATCH" new z 2>&1)
    if [ $? -ne 0 ] && grep -q "$reason" <<<"$out"; then pass "new refuses: $*"; else flunk "new on $*: $out"; fi
    out=$(run env "$@" "$SCRATCH" check 2>&1); rc=$?
    if [ $rc -eq 0 ] && grep -q "$reason.*not checked" <<<"$out" && ! grep -q '^scratch:' <<<"$out"; then
        pass "check skips: $*"
    else flunk "check on $*: rc=$rc $out"; fi
}
refused_safe 'not an absolute path' BLINK_SCRATCH_ROOT=/
refused_safe 'not named blink-probe' BLINK_SCRATCH_ROOT="$HOME"
refused_safe 'not named blink-probe' BLINK_SCRATCH_ROOT="$HOME/"

H=$WORK/h/$P
mkdir -p "$H/home" "$WORK/h/alias"; touch "$H/home/precious"
ln -s "$WORK/h" "$WORK/h/alias/up"
refused 'not an absolute path' BLINK_SCRATCH_ROOT=relative/blink-probe-a
refused 'not named blink-probe' BLINK_SCRATCH_ROOT="$WORK/tmp"
mkdir -p "$WORK/other/blink-probe-$user-not"
refused 'not named blink-probe' BLINK_SCRATCH_ROOT="$WORK/other/blink-probe-$user-not"
refused 'not named blink-probe' BLINK_SCRATCH_ROOT="$WORK/other/blink-probe-x"
refused 'holds \. or \.\.' BLINK_SCRATCH_ROOT="$WORK/tmp/../tmp/$P"
refused 'holds \. or \.\.' BLINK_SCRATCH_ROOT="$WORK/./tmp/$P"
refused 'holds //' BLINK_SCRATCH_ROOT="$WORK//tmp/$P"
refused 'no parent dir' BLINK_SCRATCH_ROOT="$WORK/nothere/$P"
mkdir -p "$WORK/target/$P/d" "$WORK/sym"
ln -s "$WORK/target/$P" "$WORK/sym/$P"
refused 'is a symlink' BLINK_SCRATCH_ROOT="$WORK/sym/$P"
mkdir -p "$WORK/file"; touch "$WORK/file/$P"
refused 'is not a dir' BLINK_SCRATCH_ROOT="$WORK/file/$P"
refused 'holds \$HOME' HOME="$H/home" BLINK_SCRATCH_ROOT="$H"
refused 'holds \$HOME' HOME="$H" BLINK_SCRATCH_ROOT="$H"
refused 'holds \$HOME' HOME="$WORK/h/./$P/home" BLINK_SCRATCH_ROOT="$H"
refused 'holds \$HOME' HOME="$WORK/h//$P/home" BLINK_SCRATCH_ROOT="$H"
refused 'holds \$HOME' HOME="$H/home" BLINK_SCRATCH_ROOT="$WORK/h/alias/up/$P"
refused 'holds \$HOME' HOME="$WORK/h/alias/up/$P/home" BLINK_SCRATCH_ROOT="$H"
# With no HOME there is no home to lose; the guard must not die on it.
mkdir -p "$WORK/nohome"
out=$(run env -u HOME BLINK_SCRATCH_ROOT="$WORK/nohome/$P" "$SCRATCH" new z 2>&1)
if [ "$out" = "$WORK/nohome/$P/z" ]; then pass "new with HOME unset"; else flunk "HOME unset: $out"; fi
[ -d "$WORK/target/$P/d" ] && pass "a symlinked root's target stays" || flunk "symlinked root target removed"
[ -f "$H/home/precious" ] && pass "a fake HOME inside the root stays" || flunk "fake HOME removed"

# an explicit root of the right shape works
mkdir -p "$WORK/home"
alt="$WORK/home/$P"
p=$(run env BLINK_SCRATCH_ROOT="$alt" "$SCRATCH" new a)
[ "$p" = "$alt/a" ] && [ -d "$p" ] && pass "BLINK_SCRATCH_ROOT sets the root" || flunk "override root printed '$p'"

if [ $fail -ne 0 ]; then echo "test_scratch: FAILED"; exit 1; fi
echo "test_scratch: all passed"
