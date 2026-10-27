#!/bin/bash
# Proves scripts/scratch.sh: `new` makes a probe dir under one root and prints
# its path, `clean` removes one dir or all of them, `check` prints each dir's
# size, warns past the limit and on a tmpfs root, and exits 0 even then, and
# every command refuses a root that is "/", $HOME, a symlink, or not named
# blink-probe-*. Each root here is under a mktemp dir.
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
root="$WORK/tmp/blink-probe-$user"

# new: default root under TMPDIR, path on stdout
p=$(run "$SCRATCH" new probe1)
if [ "$p" = "$root/probe1" ] && [ -d "$p" ]; then pass "new makes the dir under TMPDIR"; else flunk "new printed '$p'"; fi
p2=$(run "$SCRATCH" new probe1)
[ "$p2" = "$p" ] && pass "new on an existing dir prints its path" || flunk "second new printed '$p2'"
for bad in '' . .. a/b ../x '-x'; do
    if run "$SCRATCH" new "$bad" >/dev/null 2>&1; then flunk "new accepted name '$bad'"; else pass "new refuses name '$bad'"; fi
done

# check: sizes, no warning under the limit, warning past it, exit 0
dd if=/dev/zero of="$p/fill" bs=1024 count=64 status=none
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
[ $rc -eq 0 ] && pass "check exits 0 on a bad limit" || flunk "check bad limit rc=$rc"

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

# hostile roots: refused by new and clean, check exits 0 and touches nothing
mkdir -p "$WORK/home/blink-probe-x" "$WORK/target/blink-probe-y/d"
ln -s "$WORK/target/blink-probe-y" "$WORK/tmp/blink-probe-link"
for hostile in / "$HOME" "$HOME/" "$WORK/tmp" relative/blink-probe-a "$WORK/tmp/blink-probe-link" \
               "$WORK/tmp/blink-probe-a/.." "$WORK/home/notprobe"; do
    if run env BLINK_SCRATCH_ROOT="$hostile" "$SCRATCH" new z >/dev/null 2>&1; then
        flunk "new accepted root '$hostile'"
    else pass "new refuses root '$hostile'"; fi
    if run env BLINK_SCRATCH_ROOT="$hostile" "$SCRATCH" clean --all >/dev/null 2>&1; then
        flunk "clean --all accepted root '$hostile'"
    else pass "clean --all refuses root '$hostile'"; fi
    run env BLINK_SCRATCH_ROOT="$hostile" "$SCRATCH" check >/dev/null 2>&1 \
        && pass "check exits 0 on root '$hostile'" || flunk "check rc on root '$hostile'"
done
[ -d "$WORK/target/blink-probe-y/d" ] && pass "a symlinked root's target stays" || flunk "symlinked root target removed"
[ -d "$HOME" ] || flunk "HOME is gone"

# an explicit root of the right shape works
alt="$WORK/home/blink-probe-x"
p=$(run env BLINK_SCRATCH_ROOT="$alt" "$SCRATCH" new a)
[ "$p" = "$alt/a" ] && [ -d "$p" ] && pass "BLINK_SCRATCH_ROOT sets the root" || flunk "override root printed '$p'"

if [ $fail -ne 0 ]; then echo "test_scratch: FAILED"; exit 1; fi
echo "test_scratch: all passed"
