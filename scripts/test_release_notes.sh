#!/bin/bash
# Proves scripts/release_notes.sh prints every CHANGELOG section of one
# version in file order, drops the version suffix from each heading, trims
# the blank edges, adds the compare link only when given a previous tag,
# fails with no stdout for a version without a section, and never matches a
# version that only shares a prefix. Runs on a fixture changelog, never on
# the real CHANGELOG.md.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

CL="$WORK/CHANGELOG.md"
cat > "$CL" <<'EOF'
# Blink Changelog

Intro text that no release should include.

## Breaking Changes (v0.55.0)

- Removed `old_thing`.

## What's New (v0.55.0)

- Added `new_thing` (see v0.54.0 for context).

  Indented detail.

## Fixes (v0.55.0)

- Fixed a crash.

## What's New (v0.5.0)

- Five-oh only.

## What's New (v0.5.01)

- Five-oh-one only.

## Fixes (v0.54.0)

- Older fix.
EOF

run() {
    CHANGELOG="$CL" ./scripts/release_notes.sh "$@" > "$WORK/out.txt" 2> "$WORK/err.txt"
    rc=$?
}

check() {
    name="$1"; ok="$2"
    if [ "$ok" -eq 0 ]; then
        echo "PASS $name"
    else
        echo "FAIL $name"
        sed 's/^/    out: /' "$WORK/out.txt"
        sed 's/^/    err: /' "$WORK/err.txt"
        fail=1
    fi
}

same() { cmp -s "$WORK/out.txt" "$WORK/want.txt"; echo $?; }

cat > "$WORK/want.txt" <<'EOF'
## Breaking Changes

- Removed `old_thing`.

## What's New

- Added `new_thing` (see v0.54.0 for context).

  Indented detail.

## Fixes

- Fixed a crash.
EOF
run v0.55.0
check "sections of one version, suffix stripped, edges trimmed" "$(( rc != 0 ? 1 : $(same) ))"

cat > "$WORK/want.txt" <<'EOF'
## What's New

- Five-oh only.
EOF
run v0.5.0
check "short version does not match v0.55.0 or v0.5.01" "$(( rc != 0 ? 1 : $(same) ))"

cat > "$WORK/want.txt" <<'EOF'
## What's New

- Five-oh-one only.
EOF
run v0.5.01
check "v0.5.01 does not match v0.5.0" "$(( rc != 0 ? 1 : $(same) ))"

cat > "$WORK/want.txt" <<'EOF'
## Fixes

- Older fix.

**Full Changelog**: https://github.com/blinklang/blink/compare/v0.53.0...v0.54.0
EOF
run v0.54.0 v0.53.0
check "previous tag adds the compare link after a blank line" "$(( rc != 0 ? 1 : $(same) ))"

run v0.54.0
if [ "$rc" -eq 0 ] && ! grep -q 'Full Changelog' "$WORK/out.txt"; then ok=0; else ok=1; fi
check "no previous tag, no compare link" "$ok"

run v9.9.9
if [ "$rc" -ne 0 ] && [ ! -s "$WORK/out.txt" ] && grep -q 'v9.9.9' "$WORK/err.txt"; then ok=0; else ok=1; fi
check "missing version fails, empty stdout, message names it" "$ok"

run v9.9.9 v0.55.0
if [ "$rc" -ne 0 ] && [ ! -s "$WORK/out.txt" ]; then ok=0; else ok=1; fi
check "missing version with a previous tag still prints nothing" "$ok"

CHANGELOG="$WORK/none.md" ./scripts/release_notes.sh v0.55.0 > "$WORK/out.txt" 2> "$WORK/err.txt"
rc=$?
if [ "$rc" -ne 0 ] && [ ! -s "$WORK/out.txt" ] && [ -s "$WORK/err.txt" ]; then ok=0; else ok=1; fi
check "missing changelog file fails with a message" "$ok"

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "release-notes: ok"
