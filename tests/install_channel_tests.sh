#!/bin/sh
# Channel picker + versioned-lib suffix for install.sh.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required" >&2
    exit 1
}

FLYLINE_INSTALL_SH_LIB=1
# shellcheck disable=SC1091
. ./install.sh

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

fixture="tests/install_releases.json"

got="$(pick_release_tag_from_json dev < "$fixture")"
[ "$got" = "dev-20260815-bbbbbbb" ] || fail "dev channel picked '$got'"

got="$(pick_release_tag_from_json prerelease < "$fixture")"
[ "$got" = "multishell-v1.3.0" ] || fail "prerelease channel picked '$got'"

if pick_release_tag_from_json stable < "$fixture"; then
    fail "stable channel should be rejected by the JSON picker"
fi

if printf '%s' '[]' | pick_release_tag_from_json dev; then
    fail "empty release list should fail"
fi

[ "$(lib_version_suffix "multishell-v1.2.0" /tmp libflyline.so)" = "1.2.0" ] \
    || fail "product tag suffix"
[ "$(lib_version_suffix "v1.2.0" /tmp libflyline.so)" = "1.2.0" ] \
    || fail "v-prefixed suffix"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: >"${tmp}/libflyline.so.1.2.0"
[ "$(lib_version_suffix "dev-20260816-abc1234" "$tmp" libflyline.so)" = "1.2.0" ] \
    || fail "dev tag glob suffix"
if lib_version_suffix "dev-20260816-abc1234" "$tmp" libflyline.dylib; then
    fail "dev glob should fail when no matching lib exists"
fi

# Leftover 1.1.0 plus the new 1.2.0 must not be globbed together (lexicographic
# first would be 1.1.0). The installer globs the archive staging dir only.
: >"${tmp}/libflyline.so.1.1.0"
if lib_version_suffix "dev-20260816-abc1234" "$tmp" libflyline.so; then
    fail "dev glob should fail when more than one versioned lib is present"
fi
stage="${tmp}/stage"
mkdir -p "$stage"
: >"${stage}/libflyline.so.1.2.0"
[ "$(lib_version_suffix "dev-20260816-abc1234" "$stage" libflyline.so)" = "1.2.0" ] \
    || fail "dev glob of archive staging dir"

# Full installer: leftover 1.1.0 in dest, archive contains 1.2.0.
os="$(detect_os)"
arch="$(detect_arch)"
if [ "$os" = "linux" ]; then
    libc="$(detect_libc)"
    case "$arch" in
        armv7) target="armv7-unknown-linux-gnueabihf" ;;
        *) target="${arch}-unknown-linux-${libc}" ;;
    esac
    if is_supported_target "$target"; then
        scratch="${tmp}/leftover-install"
        dest="${scratch}/lib"
        assets="${scratch}/assets"
        pkg="${scratch}/pkg"
        home="${scratch}/home"
        mkdir -p "$dest" "$assets" "$pkg/scripts" "$home"
        : >"${dest}/libflyline.so.1.1.0"
        : >"${pkg}/libflyline.so.1.2.0"
        : >"${pkg}/flyline-standalone"
        chmod +x "${pkg}/flyline-standalone"
        : >"${pkg}/scripts/flyline.zsh"
        : >"${pkg}/scripts/flyline.fish"
        : >"${pkg}/LICENSE-MIT"
        : >"${pkg}/LICENSE-GPLv3"
        : >"${pkg}/UPSTREAM_BASE.toml"
        tag="dev-20260816-abc1234"
        archive="libflyline-${tag}-${target}.tar.gz"
        if is_system_bash_pre_4_4 && is_supported_pre_bash_4_4_target "$target"; then
            archive="libflyline-${tag}-${target}_pre_bash_4_4.tar.gz"
        fi
        tar czf "${assets}/${archive}" -C "$pkg" .
        (cd "$assets" && sha256sum "$archive" > "${archive}.sha256")
        out="${scratch}/install.out"
        if ! HOME="$home" FLYLINE_INSTALL_DIR="$dest" FLYLINE_ASSET_BASE="$assets" \
            FLYLINE_INSTALL_VERSION="$tag" sh ./install.sh >"$out" 2>&1; then
            cat "$out" >&2
            fail "leftover install failed"
        fi
        link="$(readlink "${dest}/libflyline.so")"
        [ "$link" = "libflyline.so.1.2.0" ] || fail "leftover install linked ${link}"
        [ -f "${dest}/libflyline.so.1.1.0" ] || fail "leftover 1.1.0 should remain"
    fi
fi

echo "install_channel_tests: ok"
