#!/bin/bash
# Checks that a release version may be released: it is vX.Y.Z, it equals
# v + VERSION, and the remote has no tag of that name yet. `task release` and
# the release workflow both run it, so the two cannot drift apart.
# Usage: scripts/release_check.sh vX.Y.Z
# VERSION_FILE and RELEASE_REMOTE (default: VERSION, origin) are for the self-test.
set -u
cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
    echo "usage: $0 vX.Y.Z" >&2
    exit 2
fi
version="$1"
version_file="${VERSION_FILE:-VERSION}"
remote="${RELEASE_REMOTE:-origin}"

if ! printf '%s\n' "$version" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "release_check: $version is not vX.Y.Z" >&2
    exit 1
fi
want="v$(tr -d '\n' < "$version_file")"
if [ "$version" != "$want" ]; then
    echo "release_check: $version does not match VERSION ($want); update VERSION first" >&2
    exit 1
fi
# ls-remote exits 2 for "no such ref" with --exit-code; any other failure
# means we could not look, which must not read as "no tag".
git ls-remote --exit-code --tags "$remote" "refs/tags/$version" > /dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "release_check: $remote already has tag $version" >&2
    exit 1
fi
if [ "$rc" -ne 2 ]; then
    echo "release_check: cannot read the tags of $remote (git ls-remote exit $rc)" >&2
    exit 1
fi
