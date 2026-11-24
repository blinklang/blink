#!/bin/sh
# The pinned gen0 as a GitHub release asset, so a machine without a seed
# compiler (a CI runner) gets build/gen0 without a bootstrap.
#
#   scripts/gen0_asset.sh fetch          download the asset for the pin in
#                                        scripts/gen0_pin.sh, check its sha256,
#                                        install it as build/gen0
#   scripts/gen0_asset.sh pack <dir>     pack build/gen0 into <dir> as the
#                                        asset and its .sha256 (re-pin step)
#
# The asset is build/gen0 exactly as scripts/gen0.sh installs it, .provenance
# included, so `task gen0` finds it current and does not rebuild it.
#
# Env:
#   BLINK_GEN0_REPO   GitHub repo that holds the release (default: blinklang/blink)
#   BLINK_GEN0_ASSET  local asset file to install in place of the download
#   BLINK_GEN0_FORCE  non-empty installs even when build/gen0 has the pin
set -eu

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
. "$ROOT_DIR/scripts/gen0_pin.sh"
OUT="$ROOT_DIR/build/gen0"
ASSET="blink-$GEN0_TAG-linux-x86_64.tar.gz"

die() { echo "gen0_asset: ERROR $*" >&2; exit 1; }

prov_get() { sed -n "s/^$1=//p" "$2/.provenance" 2>/dev/null | head -1; }

pack() {
    DEST="$1"
    [ -f "$OUT/.provenance" ] || die "build/gen0 has no .provenance; run task gen0 first"
    [ "$(prov_get tag "$OUT")" = "$GEN0_TAG" ] \
        || die "build/gen0 is $(prov_get tag "$OUT"), the pin is $GEN0_TAG"
    MTIME="$(prov_get built_utc "$OUT")"
    [ -n "$MTIME" ] || die "build/gen0/.provenance has no built_utc; rebuild it with task gen0"
    mkdir -p "$DEST"
    # Fixed order, owner and mtime keep the asset the same for the same tree.
    (cd "$ROOT_DIR/build" && tar --sort=name --owner=0 --group=0 --numeric-owner \
        --mtime="$MTIME" -cf - gen0) | gzip -9n > "$DEST/$ASSET"
    (cd "$DEST" && sha256sum "$ASSET" > "$ASSET.sha256")
    echo "gen0_asset: packed $DEST/$ASSET"
    echo "gen0_asset: set GEN0_ASSET_SHA256=$(cut -d' ' -f1 "$DEST/$ASSET.sha256") in scripts/gen0_pin.sh"
}

fetch() {
    if [ -z "${BLINK_GEN0_FORCE:-}" ] && [ -x "$OUT/bin/blinkc" ] \
        && [ "$(prov_get tag "$OUT")" = "$GEN0_TAG" ]; then
        echo "gen0_asset: build/gen0 already has $GEN0_TAG, nothing to do"
        return 0
    fi
    mkdir -p "$ROOT_DIR/build"
    TMP="$(mktemp -d "$ROOT_DIR/build/.gen0-fetch.XXXXXX")"
    trap 'rm -rf "$TMP"' EXIT
    if [ -n "${BLINK_GEN0_ASSET:-}" ]; then
        cp "$BLINK_GEN0_ASSET" "$TMP/$ASSET"
    else
        URL="https://github.com/${BLINK_GEN0_REPO:-blinklang/blink}/releases/download/$GEN0_TAG/$ASSET"
        echo "gen0_asset: downloading $URL"
        curl -fsSL --retry 3 -o "$TMP/$ASSET" "$URL" || die "download of $URL failed"
    fi
    GOT="$(sha256sum "$TMP/$ASSET" | cut -d' ' -f1)"
    [ "$GOT" = "$GEN0_ASSET_SHA256" ] \
        || die "$ASSET has sha256 $GOT, scripts/gen0_pin.sh expects $GEN0_ASSET_SHA256"
    tar -xzf "$TMP/$ASSET" -C "$TMP"
    [ "$(prov_get tag "$TMP/gen0")" = "$GEN0_TAG" ] || die "$ASSET does not hold $GEN0_TAG"
    # A clone with the tag can prove the asset came from that commit.
    TAG_SHA="$(git rev-parse -q --verify "refs/tags/$GEN0_TAG^{commit}" 2>/dev/null || true)"
    if [ -n "$TAG_SHA" ] && [ "$(prov_get tag_sha "$TMP/gen0")" != "$TAG_SHA" ]; then
        die "$ASSET was built from $(prov_get tag_sha "$TMP/gen0"), tag $GEN0_TAG is $TAG_SHA"
    fi
    rm -rf "$OUT"
    mv "$TMP/gen0" "$OUT"
    echo "gen0_asset: installed $GEN0_TAG into build/gen0 ($("$OUT/bin/blink" --version))"
}

case "${1:-}" in
    fetch) fetch ;;
    pack) [ $# -eq 2 ] || die "usage: $0 pack <dir>"; pack "$2" ;;
    *) die "usage: $0 fetch | pack <dir>" ;;
esac
