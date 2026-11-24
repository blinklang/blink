#!/bin/sh
# Install the tools a .github/workflows/release.yml job needs on a bare
# Ubuntu 24.04: the apt packages, Task and Zig. Task and Zig come from their
# release downloads at a pinned version and sha256, as apt has no Task and an
# older Zig than cross builds need (build-binaries and the -T tests).
#
#   scripts/ci_install_tools.sh
#
# Env:
#   CI_TOOLS_PREFIX   where Task and Zig go (default /usr/local); its bin/
#                     must be on PATH
set -eu

TASK_VERSION=3.54.0
TASK_SHA256=680859dbb4d881a9c72d4d9a8f510825450849af8567deacd7302c01124416fb
ZIG_VERSION=0.17.1
ZIG_SHA256=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a

[ $# -eq 0 ] || { echo "usage: ci_install_tools.sh" >&2; exit 2; }

prefix="${CI_TOOLS_PREFIX:-/usr/local}"
sudo=""
[ "$(id -u)" -eq 0 ] || sudo="sudo"

# gcc, libc6-dev and libgc-dev build and link every program. The stdlib
# archive is built with SQLite on and calls libcurl, so a program that links
# it whole (the fmt semantic run, some tests) needs both dev packages. The
# rest are the gate scripts' tools (parallel, jq, bc, rg, nm, file, ps) and
# xz for Zig.
$sudo apt-get update -q
DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -q --no-install-recommends \
    gcc libc6-dev libgc-dev libsqlite3-dev libcurl4-openssl-dev git ca-certificates curl \
    parallel jq bc ripgrep binutils file procps xz-utils

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# fetch <url> <sha256> <file>
fetch() {
    curl -fsSL --retry 3 -o "$3" "$1"
    echo "$2  $3" | sha256sum -c - > /dev/null || { echo "ci_install_tools: sha256 mismatch for $1" >&2; exit 1; }
}

fetch "https://github.com/go-task/task/releases/download/v$TASK_VERSION/task_linux_amd64.tar.gz" \
    "$TASK_SHA256" "$tmp/task.tar.gz"
tar -xzf "$tmp/task.tar.gz" -C "$tmp" task
$sudo install -m 755 "$tmp/task" "$prefix/bin/task"

fetch "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" \
    "$ZIG_SHA256" "$tmp/zig.tar.xz"
$sudo mkdir -p "$prefix/lib/zig-$ZIG_VERSION"
$sudo tar -xJf "$tmp/zig.tar.xz" -C "$prefix/lib/zig-$ZIG_VERSION" --strip-components=1
$sudo ln -sf "$prefix/lib/zig-$ZIG_VERSION/zig" "$prefix/bin/zig"

task --version
zig version
