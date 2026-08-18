#!/bin/sh
# A failed install must not leave the user without a working shell.
#
# Bash loads the library into its own process, so a half-written libflyline.so
# does not degrade to native line editing the way the zsh and fish integrations
# do: Bash aborts with a bus error while reading ~/.bashrc and every new terminal
# exits immediately. These checks drive install.sh as a subprocess against a
# hand-built release archive served from a local directory, so they need neither
# the network nor a compiled artifact.
#
# The stub libraries here are not real shared objects, so Bash integration is
# expected to be skipped in most cases below. The Docker install tests cover the
# real-library path end to end.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Mirror install.sh's platform detection so fixture archives are named the way
# install.sh will look for them.
arch="$(uname -m)"
case "$arch" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    armv7* | armhf) arch=armv7 ;;
    i386 | i486 | i586 | i686) arch=i686 ;;
    riscv64) arch=riscv64gc ;;
    ppc64le | powerpc64le) arch=powerpc64le ;;
    *) fail "unsupported architecture: $arch" ;;
esac
case "$(uname -s)" in
    Darwin)
        target="${arch}-apple-darwin"
        lib=libflyline.dylib
        ;;
    FreeBSD)
        target=x86_64-unknown-freebsd
        lib=libflyline.so
        ;;
    Linux)
        if ldd --version 2>&1 | grep -qi musl || ls /lib/ld-musl-* >/dev/null 2>&1; then
            libc=musl
        else
            libc=gnu
        fi
        case "$arch" in
            armv7) target=armv7-unknown-linux-gnueabihf ;;
            *) target="${arch}-unknown-linux-${libc}" ;;
        esac
        lib=libflyline.so
        ;;
    *) fail "unsupported OS: $(uname -s)" ;;
esac

# install.sh prefers the pre-Bash-4.4 archive on an old system Bash, and that
# build only exists for x86_64 glibc Linux.
archive_suffix=""
bash_bin="$(command -v bash 2>/dev/null || true)"
bash_major=0
bash_minor=0
if [ -n "$bash_bin" ]; then
    # Expanded by the Bash subprocess, not by this POSIX shell.
    # shellcheck disable=SC2016
    bash_version="$("$bash_bin" -c 'echo "${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]}"' 2>/dev/null || echo "0 0")"
    bash_major="${bash_version%% *}"
    bash_minor="${bash_version##* }"
fi
if [ "${bash_major:-0}" -lt 4 ] || { [ "${bash_major:-0}" -eq 4 ] && [ "${bash_minor:-0}" -lt 4 ]; }; then
    if [ "$target" = x86_64-unknown-linux-gnu ]; then
        archive_suffix=_pre_bash_4_4
    fi
fi

version=multishell-v9.9.9
packed=9.9.9
leftover=9.9.8
real_cp="$(command -v cp)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stub libraries need real bytes so a truncated copy is observable.
write_stub_lib() {
    i=0
    : >"$1"
    while [ "$i" -lt 64 ]; do
        printf 'flyline-stub-library-payload\n' >>"$1"
        i=$((i + 1))
    done
}

# Lay out an install destination that already holds an older library, plus the
# contents of a release archive that has not been packed yet.
stage_case() {
    scratch="${tmp}/$1"
    dest="${scratch}/lib"
    assets="${scratch}/assets"
    pkg="${scratch}/pkg"
    home="${scratch}/home"
    mkdir -p "$dest" "$assets" "$pkg/scripts" "$home"
    write_stub_lib "${dest}/${lib}.${leftover}"
    ln -s "${lib}.${leftover}" "${dest}/${lib}"
    : >"${pkg}/flyline-standalone"
    chmod +x "${pkg}/flyline-standalone"
    : >"${pkg}/scripts/flyline.zsh"
    : >"${pkg}/scripts/flyline.fish"
    : >"${pkg}/LICENSE-MIT"
    : >"${pkg}/LICENSE-GPLv3"
    : >"${pkg}/UPSTREAM_BASE.toml"
    archive="libflyline-${version}-${target}${archive_suffix}.tar.gz"
}

seal_archive() {
    tar czf "${assets}/${archive}" -C "$pkg" .
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$assets" && sha256sum "$archive" >"${archive}.sha256")
    else
        (cd "$assets" && shasum -a 256 "$archive" >"${archive}.sha256")
    fi
}

run_install() {
    out="$1"
    status=0
    env ${2:+PATH="$2:$PATH"} \
        FLYLINE_TEST_LIB="$lib" FLYLINE_TEST_REAL_CP="$real_cp" \
        FLYLINE_TEST_LOG="${scratch}/truncated" \
        HOME="$home" FLYLINE_INSTALL_DIR="$dest" FLYLINE_ASSET_BASE="$assets" \
        FLYLINE_INSTALL_VERSION="$version" sh ./install.sh >"$out" 2>&1 || status=$?
    if grep -q 'Asset not found' "$out"; then
        cat "$out" >&2
        fail "fixture archive name did not match the target install.sh detected (${target})"
    fi
    echo "$status"
}

# 1. The happy path still replaces the symlink and keeps the older library, which
#    is what upstream does today.
stage_case happy
write_stub_lib "${pkg}/${lib}.${packed}"
seal_archive
out="${tmp}/happy.out"
[ "$(run_install "$out")" = 0 ] || { cat "$out" >&2; fail "install failed"; }
[ "$(readlink "${dest}/${lib}")" = "${lib}.${packed}" ] \
    || fail "symlink points at $(readlink "${dest}/${lib}")"
[ -f "${dest}/${lib}.${leftover}" ] || fail "older library should be left alone"

# 2. A copy that dies partway must not damage the library the existing symlink
#    points at. Re-installing the same version is the documented upgrade path, so
#    that library is the very file being written.
shim="${tmp}/shim"
mkdir -p "$shim"
cat >"${shim}/cp" <<'SHIM'
#!/bin/sh
# Emulate a copy interrupted midway through the library, and behave normally for
# everything else (install.sh also uses cp to fetch local release assets).
case "$2" in
    */.flyline-tmp.*"${FLYLINE_TEST_LIB}".*)
        size="$(wc -c < "$1")"
        head -c "$((size / 2))" "$1" > "$2"
        echo "$2" >> "$FLYLINE_TEST_LOG"
        exit 1
        ;;
esac
exec "$FLYLINE_TEST_REAL_CP" "$@"
SHIM
chmod +x "${shim}/cp"

stage_case interrupted
rm -f "${dest}/${lib}"
write_stub_lib "${dest}/${lib}.${packed}"
ln -s "${lib}.${packed}" "${dest}/${lib}"
live_before="$(cat "${dest}/${lib}.${packed}")"
write_stub_lib "${pkg}/${lib}.${packed}"
printf 'extra-bytes-so-the-packaged-copy-differs\n' >>"${pkg}/${lib}.${packed}"
seal_archive
out="${tmp}/interrupted.out"
[ "$(run_install "$out" "$shim")" != 0 ] \
    || { cat "$out" >&2; fail "interrupted copy should fail the install"; }
# Prove the interruption actually landed on the library, not some other file.
grep -q "${lib}.${packed}\$" "${scratch}/truncated" \
    || fail "the interrupted copy did not target ${lib}.${packed}"
[ "$(cat "${dest}/${lib}.${packed}")" = "$live_before" ] \
    || fail "interrupted copy damaged the library already in use"
[ "$(readlink "${dest}/${lib}")" = "${lib}.${packed}" ] \
    || fail "interrupted copy moved the symlink"
for leftover_tmp in "${dest}"/.flyline-tmp.* "${dest}"/scripts/.flyline-tmp.*; do
    [ -e "$leftover_tmp" ] && fail "temp file left behind: ${leftover_tmp}"
done

# 3. An archive with no versioned library must abort rather than fall through to
#    the unversioned-library branch, which a previous install's symlink also
#    satisfies. Falling through would report success while leaving the old
#    library in use.
stage_case no-versioned-lib
seal_archive
out="${tmp}/no-versioned-lib.out"
[ "$(run_install "$out")" != 0 ] \
    || { cat "$out" >&2; fail "archive without a versioned library should fail"; }
[ "$(readlink "${dest}/${lib}")" = "${lib}.${leftover}" ] \
    || fail "symlink should be untouched, got $(readlink "${dest}/${lib}")"

# 4. An archive that genuinely ships an unversioned library is still accepted,
#    because the check above looks at the unpacked archive rather than the
#    install directory.
stage_case unversioned-lib
write_stub_lib "${pkg}/${lib}"
seal_archive
out="${tmp}/unversioned-lib.out"
[ "$(run_install "$out")" = 0 ] \
    || { cat "$out" >&2; fail "archive with an unversioned library should install"; }
grep -q "Archive contains ${lib}" "$out" || fail "installer did not report the unversioned library"

echo "install_resilience_tests: ok"
