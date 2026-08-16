#!/bin/sh
# Channel picker + versioned-lib suffix for install.sh.
#
# Version numbers here are fixtures, not Cargo.toml. Cutting a product
# release (1.2.1, 1.3.0, …) must not require edits to this file.
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
[ "$got" = "dev-19990101-bbbbbbb" ] || fail "dev channel picked '$got'"

got="$(pick_release_tag_from_json prerelease < "$fixture")"
[ "$got" = "multishell-v9.1.0" ] || fail "prerelease channel picked '$got'"

if pick_release_tag_from_json stable < "$fixture"; then
    fail "stable channel should be rejected by the JSON picker"
fi

if printf '%s' '[]' | pick_release_tag_from_json dev; then
    fail "empty release list should fail"
fi

# Prefix strip is a string transform; the X.Y.Z is unrelated to the crate.
[ "$(lib_version_suffix "multishell-v9.8.7" /tmp libflyline.so)" = "9.8.7" ] \
    || fail "product tag suffix"
[ "$(lib_version_suffix "v9.8.7" /tmp libflyline.so)" = "9.8.7" ] \
    || fail "v-prefixed suffix"

# Packed vs leftover suffixes: leftover must sort first under POSIX glob
# (`8.1.0` before `8.2.0`). Independent of whatever Cargo.toml says.
packed="8.2.0"
leftover="8.1.0"
dev_tag="dev-19990101-0fedcba"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: >"${tmp}/libflyline.so.${packed}"
[ "$(lib_version_suffix "$dev_tag" "$tmp" libflyline.so)" = "$packed" ] \
    || fail "dev tag glob suffix"
if lib_version_suffix "$dev_tag" "$tmp" libflyline.dylib; then
    fail "dev glob should fail when no matching lib exists"
fi

: >"${tmp}/libflyline.so.${leftover}"
if lib_version_suffix "$dev_tag" "$tmp" libflyline.so; then
    fail "dev glob should fail when more than one versioned lib is present"
fi
stage="${tmp}/stage"
mkdir -p "$stage"
: >"${stage}/libflyline.so.${packed}"
[ "$(lib_version_suffix "$dev_tag" "$stage" libflyline.so)" = "$packed" ] \
    || fail "dev glob of archive staging dir"

# Full installer: dest already has leftover; archive contains packed.
os="$(detect_os)"
arch="$(detect_arch)"
[ "$os" = "linux" ] || fail "leftover-lib installer coverage requires linux, got ${os}"
libc="$(detect_libc)"
case "$arch" in
    armv7) target="armv7-unknown-linux-gnueabihf" ;;
    *) target="${arch}-unknown-linux-${libc}" ;;
esac
is_supported_target "$target" || fail "unsupported leftover-lib test target ${target}"

scratch="${tmp}/leftover-install"
dest="${scratch}/lib"
assets="${scratch}/assets"
pkg="${scratch}/pkg"
home="${scratch}/home"
mkdir -p "$dest" "$assets" "$pkg/scripts" "$home"
: >"${dest}/libflyline.so.${leftover}"
ln -s "libflyline.so.${leftover}" "${dest}/libflyline.so"
: >"${pkg}/libflyline.so.${packed}"
: >"${pkg}/flyline-standalone"
chmod +x "${pkg}/flyline-standalone"
: >"${pkg}/scripts/flyline.zsh"
: >"${pkg}/scripts/flyline.fish"
: >"${pkg}/LICENSE-MIT"
: >"${pkg}/LICENSE-GPLv3"
: >"${pkg}/UPSTREAM_BASE.toml"
archive="libflyline-${dev_tag}-${target}.tar.gz"
if is_system_bash_pre_4_4 && is_supported_pre_bash_4_4_target "$target"; then
    archive="libflyline-${dev_tag}-${target}_pre_bash_4_4.tar.gz"
fi
tar czf "${assets}/${archive}" -C "$pkg" .
(cd "$assets" && sha256sum "$archive" > "${archive}.sha256")
out="${scratch}/install.out"
if ! HOME="$home" FLYLINE_INSTALL_DIR="$dest" FLYLINE_ASSET_BASE="$assets" \
    FLYLINE_INSTALL_VERSION="$dev_tag" sh ./install.sh >"$out" 2>&1; then
    cat "$out" >&2
    fail "leftover install failed"
fi
grep -q "Creating symlink libflyline.so -> libflyline.so.${packed}" "$out" \
    || fail "installer did not report symlink to packed ${packed}"
! grep -q "Creating symlink libflyline.so -> libflyline.so.${leftover}" "$out" \
    || fail "installer reported symlink to leftover ${leftover}"
link="$(readlink "${dest}/libflyline.so")"
[ "$link" = "libflyline.so.${packed}" ] || fail "leftover install linked ${link}"
[ -f "${dest}/libflyline.so.${leftover}" ] || fail "leftover ${leftover} should remain"
[ -f "${dest}/libflyline.so.${packed}" ] || fail "packed ${packed} should be installed"

echo "install_channel_tests: ok"
