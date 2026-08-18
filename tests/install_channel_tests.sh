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

# Full installer runs against this host's own target so the coverage works on
# Linux, macOS and FreeBSD rather than only where the release matrix runs.
os="$(detect_os)"
arch="$(detect_arch)"
case "$os" in
    darwin)
        target="${arch}-apple-darwin"
        lib="libflyline.dylib"
        ;;
    freebsd)
        target="x86_64-unknown-freebsd"
        lib="libflyline.so"
        ;;
    *)
        libc="$(detect_libc)"
        case "$arch" in
            armv7) target="armv7-unknown-linux-gnueabihf" ;;
            *) target="${arch}-unknown-linux-${libc}" ;;
        esac
        lib="libflyline.so"
        ;;
esac
is_supported_target "$target" || fail "no release archive is built for ${target}"

# Stage a release archive by hand, then install it over a previous install that
# left an older versioned library behind.
stage_archive() {
    scratch="$1"
    dest="${scratch}/lib"
    assets="${scratch}/assets"
    pkg="${scratch}/pkg"
    home="${scratch}/home"
    mkdir -p "$dest" "$assets" "$pkg/scripts" "$home"
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
}

seal_archive() {
    tar czf "${assets}/${archive}" -C "$pkg" .
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$assets" && sha256sum "$archive" > "${archive}.sha256")
    else
        (cd "$assets" && shasum -a 256 "$archive" > "${archive}.sha256")
    fi
}

run_installer() {
    out="$1"
    status=0
    HOME="$home" FLYLINE_INSTALL_DIR="$dest" FLYLINE_ASSET_BASE="$assets" \
        FLYLINE_INSTALL_VERSION="$dev_tag" sh ./install.sh >"$out" 2>&1 || status=$?
    echo "$status"
}

stage_archive "${tmp}/leftover-install"
: >"${dest}/${lib}.${leftover}"
ln -s "${lib}.${leftover}" "${dest}/${lib}"
: >"${pkg}/${lib}.${packed}"
seal_archive
out="${tmp}/leftover.out"
if [ "$(run_installer "$out")" != 0 ]; then
    cat "$out" >&2
    fail "leftover install failed"
fi
grep -q "Creating symlink ${lib} -> ${lib}.${packed}" "$out" \
    || fail "installer did not report symlink to packed ${packed}"
! grep -q "Creating symlink ${lib} -> ${lib}.${leftover}" "$out" \
    || fail "installer reported symlink to leftover ${leftover}"
link="$(readlink "${dest}/${lib}")"
[ "$link" = "${lib}.${packed}" ] || fail "leftover install linked ${link}"
[ -f "${dest}/${lib}.${leftover}" ] || fail "leftover ${leftover} should remain"
[ -f "${dest}/${lib}.${packed}" ] || fail "packed ${packed} should be installed"

# An unresolvable packaged version must abort rather than leave the previous
# install's symlink (and therefore the older library) in place.
for shape in none ambiguous tag_named; do
    stage_archive "${tmp}/reject-${shape}"
    : >"${dest}/${lib}.${leftover}"
    ln -s "${lib}.${leftover}" "${dest}/${lib}"
    case "$shape" in
        none) : ;;
        ambiguous)
            : >"${pkg}/${lib}.${packed}"
            : >"${pkg}/${lib}.${leftover}"
            ;;
        tag_named) : >"${pkg}/${lib}.${dev_tag}" ;;
    esac
    seal_archive
    out="${tmp}/reject-${shape}.out"
    [ "$(run_installer "$out")" != 0 ] \
        || { cat "$out" >&2; fail "${shape} archive should fail the install"; }
    link="$(readlink "${dest}/${lib}")"
    [ "$link" = "${lib}.${leftover}" ] \
        || fail "${shape}: symlink should be untouched, got ${link}"
done

echo "install_channel_tests: ok"
