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

echo "install_channel_tests: ok"
