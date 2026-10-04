#!/bin/sh
# Build the pinned gen0 compiler from the tag into build/gen0/.
#
# gen0 is the fixed compiler that builds the tree. It must come from the
# tag, never from a live build, so its provenance is provable. The script checks the tag out into a scratch
# worktree, bootstraps it there with the normal seed rules, then installs
# it into build/gen0/ in the installed layout:
#
#   build/gen0/bin/{blinkc,blink}
#   build/gen0/lib/{std,pkg}      stdlib sources: blinkc reads <dir of argv[0]>/lib/std
#   build/gen0/bin/lib -> ../lib
#   build/gen0/share/blink/{libblink_std.a,libblink_std.h,skip_modules.txt,runtime.h,.archive-id,native/}
#   build/gen0/{blinkc,blink,libblink_std.a,libblink_std.h}   symlinks into the above
#   build/gen0/.provenance
#
# The installed layout matters: `blink` resolves its install root two
# directories up from realpath(argv[0]). A flat build/gen0/blink would
# resolve to build/ and silently link the live archive. Do not export
# BLINK_ROOT when you run the gen0 binaries: it overrides that root.
#
# Env:
#   BLINK_GEN0_TAG    tag to pin (default: v0.54.0)
#   BLINK_GEN0_WORK   scratch dir for the worktree (default: mktemp under $TMPDIR)
#   BLINK_GEN0_SEED   path of the `blink` binary that seeds the bootstrap
#                     (default: build/blink of this tree, else `blink` on PATH).
#                     A released install can be too old to compile the tag.
#   BLINK_GEN0_FORCE  non-empty rebuilds even when .provenance is current
set -eu

CALLER_DIR="$(pwd)"
cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
TAG="${BLINK_GEN0_TAG:-v0.54.0}"
OUT="$ROOT_DIR/build/gen0"

TAG_SHA="$(git rev-parse -q --verify "refs/tags/$TAG^{commit}" 2>/dev/null || true)"
if [ -z "$TAG_SHA" ]; then
    echo "gen0: ERROR tag '$TAG' does not exist in this repository" >&2
    exit 1
fi
TAG_SHORT="$(echo "$TAG_SHA" | cut -c1-8)"

sha_of() { sha256sum "$1" | awk '{print $1}'; }

prov_get() { sed -n "s/^$1=//p" "$OUT/.provenance" 2>/dev/null | head -1; }

# One hash over every installed file and symlink, so a missing stdlib source
# or native sidecar also makes the install stale, not only the binaries.
tree_sha() {
    (cd "$OUT" && find . \( -type f -o -type l \) ! -name .provenance | LC_ALL=C sort \
        | while IFS= read -r f; do
            if [ -L "$f" ]; then echo "link $f -> $(readlink "$f")"; else sha256sum "$f"; fi
        done | sha256sum | awk '{print $1}')
}

provenance_current() {
    [ -f "$OUT/.provenance" ] || return 1
    [ "$(prov_get tag_sha)" = "$TAG_SHA" ] || return 1
    [ "$(prov_get tree_sha256)" = "$(tree_sha)" ] || return 1
}

if [ -z "${BLINK_GEN0_FORCE:-}" ] && provenance_current; then
    echo "gen0: up to date ($TAG @ $TAG_SHORT), nothing to do"
    exit 0
fi

if [ -n "${BLINK_GEN0_WORK:-}" ]; then
    # Absolute, relative to the caller: the script changes directory later.
    WORK="$(cd "$CALLER_DIR" && mkdir -p "$BLINK_GEN0_WORK" && cd "$BLINK_GEN0_WORK" && pwd)"
else
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/blink-gen0.XXXXXX")"
fi
WT="$WORK/tree"

remove_worktree() {
    git worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
    git worktree prune
}
cleanup() {
    cd "$ROOT_DIR"
    remove_worktree
    if [ -z "${BLINK_GEN0_WORK:-}" ]; then
        rm -rf "$WORK"
    fi
}
# A signal trap that only cleans up would let the script run on; exit
# instead so the EXIT trap does the cleanup once.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The compiler takes the FIRST /src/ in a path as the module root.
case "$WT/" in
    */src/*)
        echo "gen0: ERROR scratch dir '$WT' has a /src/ segment; set BLINK_GEN0_WORK or TMPDIR elsewhere" >&2
        exit 1
        ;;
esac

# A leftover worktree from an aborted run must not shadow the tag checkout.
if [ -e "$WT" ]; then
    remove_worktree
fi
git worktree add --detach --quiet "$WT" "$TAG_SHA"

SEED="${BLINK_GEN0_SEED:-}"
if [ -z "$SEED" ] && [ -x "$ROOT_DIR/build/blink" ]; then
    SEED="$ROOT_DIR/build/blink"
fi
if [ -z "$SEED" ]; then
    SEED="$(command -v blink 2>/dev/null || true)"
fi
if [ -z "$SEED" ] || [ ! -x "$SEED" ]; then
    echo "gen0: ERROR no seed compiler: set BLINK_GEN0_SEED=<path to blink>, build this tree, or put blink on PATH" >&2
    exit 1
fi
SEED="$(readlink -f "$SEED")"
# bootstrap.sh takes its seed from `blink` on PATH. A symlink (not a copy)
# keeps realpath(argv[0]) inside the seed's own tree so it finds its archive.
mkdir -p "$WORK/seed"
ln -sf "$SEED" "$WORK/seed/blink"
export PATH="$WORK/seed:$PATH"
SEED_LINE="seed=$SEED ($("$SEED" --version 2>/dev/null | head -1)) sha256=$(sha_of "$SEED")"

if [ ! -f "$WT/VERSION" ]; then
    echo "gen0: ERROR tag '$TAG' has no VERSION file; this script cannot build it" >&2
    exit 1
fi
VERSION="$(tr -d '\n' < "$WT/VERSION")"
STAMP="$VERSION-gen0+$TAG_SHORT"

# Everything below runs inside the worktree, exactly as `task bootstrap`
# runs in the main tree: the archive builder and the std-cache use
# cwd-relative build/ paths. BLINK_ROOT stays unset so the seed compiler
# still finds its own archive. An empty BLINK_CACHE_DIR turns the obj cache
# off so no shared cache content can leak into the pinned build.
cd "$WT"
unset BLINK_ROOT BLINK_BOOTSTRAP_LEGACY
export BLINK_CACHE_DIR=""

echo "gen0: bootstrapping $TAG @ $TAG_SHORT in $WT"
./bootstrap/bootstrap.sh

# A fixed version stamp keeps the binaries reproducible.
stamp_version() {
    sed -i "s/blink_cli_version = \"dev\"/blink_cli_version = \"$STAMP\"/" "$1"
    if ! grep -q "blink_cli_version = \"$STAMP\"" "$1"; then
        echo "gen0: ERROR version stamp not applied to $1" >&2
        exit 1
    fi
}
link_archived() {
    cc -o "$1" "$2" -Ibuild build/libblink_std.a -lm -lgc -pthread -Wl,--gc-sections
}

# bootstrap.sh leaves a stdlib archive from the SEED compiler and a blinkc
# that links against it. The pinned binaries must carry only code the
# tag's compiler emitted, so: build the CLI from the tag, rebuild the
# archive with it, re-emit blinkc against that archive, rebuild the archive
# once more so its identity stamp names the final blinkc, then link the
# final CLI.
echo "gen0: building CLI from the tag"
build/blinkc src/cli.bl build/cli.c
stamp_version build/cli.c
cc -o build/blink build/cli.c -lm -lgc
echo "gen0: building the stdlib archive with the tag's compiler"
BLINK_FORCE_STDLIB_REBUILD=1 build/blink __build-stdlib-archive
build/blinkc --link-archive build/libblink_std.h src/blinkc_main.bl build/blinkc.c
link_archived build/blinkc build/blinkc.c
BLINK_FORCE_STDLIB_REBUILD=1 build/blink __build-stdlib-archive
build/blinkc --link-archive build/libblink_std.h src/cli.bl build/cli.c
stamp_version build/cli.c
link_archived build/blink build/cli.c

echo "gen0: installing into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/share/blink"
cp build/blinkc build/blink "$OUT/bin/"
mkdir -p "$OUT/lib"
cp -R build/lib/std build/lib/pkg "$OUT/lib/"
ln -s ../lib "$OUT/bin/lib"
# skip_modules.txt is not part of `task build`'s install, but
# `blinkc --link-archive <hdr>` reads it next to the header.
cp -L build/libblink_std.a build/libblink_std.h build/skip_modules.txt \
      build/runtime.h build/.archive-id "$OUT/share/blink/"
# Native dep sidecars, same layout `task build` installs, so a gen0 build of
# a program that imports a peeled module (std.db_sqlite) links from gen0.
# The list goes through a file so a failed `__native-deps` stops the script.
build/blink __native-deps > "$WORK/native-deps.txt"
while IFS='|' read -r NAME SRCS HDR_DIR _DEFS _GATE; do
    [ -z "$NAME" ] && continue
    DEST="$OUT/share/blink/native/$NAME"
    mkdir -p "$DEST"
    IFS=','; for SRC in $SRCS; do cp "$SRC" "$DEST/"; done; unset IFS
    if [ -d "$HDR_DIR" ]; then
        find "$HDR_DIR" -maxdepth 1 -name '*.h' -exec cp {} "$DEST/" \;
    fi
done < "$WORK/native-deps.txt"
ln -s bin/blinkc "$OUT/blinkc"
ln -s bin/blink "$OUT/blink"
ln -s share/blink/libblink_std.a "$OUT/libblink_std.a"
ln -s share/blink/libblink_std.h "$OUT/libblink_std.h"
ln -s share/blink/skip_modules.txt "$OUT/skip_modules.txt"

cat > "$OUT/.provenance" <<PROV
tag=$TAG
tag_sha=$TAG_SHA
built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
version=$STAMP
$SEED_LINE
cc=$(cc --version 2>/dev/null | head -1)
blinkc_sha256=$(sha_of "$OUT/bin/blinkc")
blink_sha256=$(sha_of "$OUT/bin/blink")
libblink_std_a_sha256=$(sha_of "$OUT/share/blink/libblink_std.a")
libblink_std_h_sha256=$(sha_of "$OUT/share/blink/libblink_std.h")
skip_modules_sha256=$(sha_of "$OUT/share/blink/skip_modules.txt")
runtime_h_sha256=$(sha_of "$OUT/share/blink/runtime.h")
tree_sha256=$(tree_sha)
PROV

echo "gen0: done"
cat "$OUT/.provenance"
