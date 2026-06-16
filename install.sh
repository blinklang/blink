#!/bin/sh
# Blink installer. Detects platform, downloads the matching release tarball
# from GitHub, and extracts it into a prefix containing bin/ + share/blink/.
#
# Usage:
#   curl -sSL https://blinklang.org/install.sh | sh
#   curl -sSL https://blinklang.org/install.sh | sh -s -- --version v0.43.0
#   curl -sSL https://blinklang.org/install.sh | sh -s -- --prefix /usr/local
#
# Defaults to prefix=$HOME/.local. With --prefix=/usr/local, may prompt for sudo.

set -eu

REPO="blinklang/blink"
VERSION=""
PREFIX="${BLINK_PREFIX:-$HOME/.local}"

err() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        -h|--help)
            cat <<EOF
Usage: install.sh [--version vX.Y.Z] [--prefix DIR]

Installs blink to <prefix>/bin/blink and <prefix>/share/blink/.
Default prefix is \$HOME/.local. Set BLINK_PREFIX to override.
EOF
            exit 0
            ;;
        *) err "unknown argument: $1" ;;
    esac
done

# Detect OS and arch.
uname_s=$(uname -s)
uname_m=$(uname -m)
case "$uname_s" in
    Linux)  os="linux" ;;
    Darwin) os="macos" ;;
    *) err "unsupported OS: $uname_s" ;;
esac
case "$uname_m" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *) err "unsupported arch: $uname_m" ;;
esac

# Linux arm64 is not yet released; bail with a clear message.
case "$os-$arch" in
    linux-x86_64|macos-x86_64|macos-aarch64) ;;
    *) err "no release tarball for $os-$arch yet" ;;
esac

target="$os-$arch"

# Pick a downloader.
if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1" -o "$2"; }
    fetch_stdout() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO "$2" "$1"; }
    fetch_stdout() { wget -qO- "$1"; }
else
    err "need curl or wget"
fi

# Resolve version. Empty => latest release tag via GitHub API.
if [ -z "$VERSION" ]; then
    api="https://api.github.com/repos/$REPO/releases/latest"
    VERSION=$(fetch_stdout "$api" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1)
    [ -n "$VERSION" ] || err "failed to resolve latest release tag from $api"
fi

asset="blink-$target.tar.gz"
url="https://github.com/$REPO/releases/download/$VERSION/$asset"

info "Installing blink $VERSION for $target → $PREFIX"

# Decide whether sudo is needed for the prefix.
need_sudo=0
if [ ! -w "$PREFIX" ] 2>/dev/null && [ ! -w "$(dirname "$PREFIX")" ] 2>/dev/null; then
    if [ "$(id -u)" -ne 0 ]; then
        need_sudo=1
    fi
fi
sudo_cmd=""
if [ "$need_sudo" -eq 1 ]; then
    command -v sudo >/dev/null 2>&1 || err "$PREFIX not writable and sudo not found"
    sudo_cmd="sudo"
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

info "Downloading $url"
fetch "$url" "$tmpdir/blink.tar.gz"

info "Extracting"
tar -xzf "$tmpdir/blink.tar.gz" -C "$tmpdir"
src="$tmpdir/blink-$target"
[ -d "$src" ] || err "tarball missing expected directory blink-$target/"

$sudo_cmd mkdir -p "$PREFIX/bin" "$PREFIX/share/blink"
$sudo_cmd cp "$src/bin/blink" "$PREFIX/bin/blink"
$sudo_cmd chmod +x "$PREFIX/bin/blink"
$sudo_cmd cp "$src/share/blink/libblink_std.a" \
            "$src/share/blink/libblink_std.h" \
            "$src/share/blink/runtime.h" \
            "$PREFIX/share/blink/"
# Identity stamp: the installed blink verifies this against its own runtime.h
# SHA at link time and rejects a stale/mismatched archive instead of silently
# linking an ABI-skewed (memory-corrupting) binary (br 105z02). Guard for
# absence so an older tarball (pre-stamp) still installs.
if [ -f "$src/share/blink/.archive-id" ]; then
    $sudo_cmd cp "$src/share/blink/.archive-id" "$PREFIX/share/blink/"
fi
# Peeled native deps (e.g. sqlite3) ship as a sidecar under
# share/blink/native/<name>/. Programs that import a peeled stdlib module
# (e.g. std.db_sqlite) need the vendored C source at compile time;
# resolve_native_dep_source() looks for it here. Copy recursively. Guard
# for absence so installing an older tarball (pre-sidecar) still succeeds.
if [ -d "$src/share/blink/native" ]; then
    $sudo_cmd cp -R "$src/share/blink/native" "$PREFIX/share/blink/"
fi

info "Installed blink to $PREFIX/bin/blink"
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) info "Note: $PREFIX/bin is not on PATH. Add it to your shell init." ;;
esac
"$PREFIX/bin/blink" --version || true
