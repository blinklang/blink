#!/bin/bash
# Proves scripts/release_check.sh accepts only a vX.Y.Z version equal to
# v + VERSION that the remote has no tag of, and names the fault on stderr
# when it rejects one. Runs on a fixture VERSION file and a local bare remote,
# never on the real VERSION or origin.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

printf '0.55.0\n' > "$WORK/VERSION"
REMOTE="$WORK/remote.git"
git init -q --bare "$REMOTE"
git init -q "$WORK/clone"
git -C "$WORK/clone" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$WORK/clone" tag v0.54.0
git -C "$WORK/clone" push -q "$REMOTE" v0.54.0

run() {
    VERSION_FILE="$WORK/VERSION" RELEASE_REMOTE="$REMOTE" ./scripts/release_check.sh "$@" \
        > "$WORK/out.txt" 2> "$WORK/err.txt"
    rc=$?
}

check() {
    name="$1"; ok="$2"
    if [ "$ok" -eq 0 ]; then
        echo "PASS $name"
    else
        echo "FAIL $name (rc=$rc)"
        sed 's/^/    err: /' "$WORK/err.txt"
        fail=1
    fi
}

run v0.55.0
if [ "$rc" -eq 0 ]; then ok=0; else ok=1; fi
check "the version of VERSION with no tag passes" "$ok"

run v0.55
if [ "$rc" -eq 1 ] && grep -q 'vX.Y.Z' "$WORK/err.txt"; then ok=0; else ok=1; fi
check "a version that is not vX.Y.Z fails" "$ok"

run 0.55.0
if [ "$rc" -eq 1 ] && grep -q 'vX.Y.Z' "$WORK/err.txt"; then ok=0; else ok=1; fi
check "a version with no v fails" "$ok"

run v0.55.1
if [ "$rc" -eq 1 ] && grep -q 'VERSION' "$WORK/err.txt"; then ok=0; else ok=1; fi
check "a version other than VERSION fails" "$ok"

printf '0.54.0\n' > "$WORK/VERSION"
run v0.54.0
if [ "$rc" -eq 1 ] && grep -q 'already has tag v0.54.0' "$WORK/err.txt"; then ok=0; else ok=1; fi
check "a version the remote has a tag of fails" "$ok"

RELEASE_REMOTE="$WORK/missing.git" VERSION_FILE="$WORK/VERSION" ./scripts/release_check.sh v0.54.0 \
    > "$WORK/out.txt" 2> "$WORK/err.txt"
rc=$?
if [ "$rc" -eq 1 ] && grep -q 'cannot read the tags' "$WORK/err.txt"; then ok=0; else ok=1; fi
check "a remote it cannot read fails, not passes" "$ok"

run
if [ "$rc" -eq 2 ]; then ok=0; else ok=1; fi
check "no version is a usage error" "$ok"

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "release-check: ok"
