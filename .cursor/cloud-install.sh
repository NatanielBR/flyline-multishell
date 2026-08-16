#!/usr/bin/env bash
# Snapshot-time bootstrap for Cursor Cloud agents.
# Idempotent: safe to re-run on a cached or partial snapshot.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- Rust (edition 2024) ---------------------------------------------------
# The stock Cursor image ships rustup with a default toolchain (1.83.0) that
# predates edition 2024. flyline pins 1.96.0 via rust-toolchain.toml; flycomp
# has no pin and fails to parse its manifest on the old default.
if ! command -v rustup >/dev/null 2>&1; then
  export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
  export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
  # shellcheck disable=SC1091
  . "$CARGO_HOME/env"
fi
rustup toolchain install 1.96.0 --profile minimal -c clippy -c rustfmt
rustup default 1.96.0

# --- Host packages for the upstream-sync test gate -------------------------
# Nested Docker (bake zsh/fish integration tests) plus local widget syntax checks.
sudo apt-get update -y
sudo apt-get install -y -o Dpkg::Options::="--force-confold" \
  zsh \
  fish \
  fuse3 \
  fuse-overlayfs \
  iptables \
  docker.io \
  docker-buildx

if [ -x /usr/sbin/iptables-legacy ]; then
  sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
  sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
fi

if [ ! -f /etc/docker/daemon.json ] || ! grep -q 'fuse-overlayfs' /etc/docker/daemon.json; then
  printf '%s\n' '{' '  "storage-driver": "fuse-overlayfs"' '}' | sudo tee /etc/docker/daemon.json >/dev/null
fi

# Ubuntu /etc/zsh/zshrc runs `compinit` without -i, which hangs the headless
# completion-daemon PTY. Must live in /etc/zsh/zshenv: tests that set ZDOTDIR
# skip ~/.zshenv, so a home-only fix still loads the global compinit.
if [ -d /etc/zsh ]; then
  sudo touch /etc/zsh/zshenv
  if ! grep -qx 'skip_global_compinit=1' /etc/zsh/zshenv; then
    printf '\n# flyline cloud: Ubuntu global zshrc compinit hangs headless daemons.\nskip_global_compinit=1\n' \
      | sudo tee -a /etc/zsh/zshenv >/dev/null
  fi
fi

# python3-argcomplete ships `#compdef -P *`, so every unknown command looks
# like a command-specific completer (<<FLYSPECIFIC>>1) and fails lib tests
# that distinguish generic file fallback. Move it fully off $fpath — renaming
# in-place to *_disabled is not enough (zsh still autoloads _*).
stash=/var/lib/flyline-cloud
sudo mkdir -p "$stash"
for f in /usr/share/zsh/vendor-completions/_python-argcomplete \
  /usr/share/zsh/vendor-completions/_python-argcomplete.disabled; do
  if [ -e "$f" ]; then
    sudo mv "$f" "$stash/$(basename "$f")"
  fi
done
rm -f "$HOME"/.zcompdump "$HOME"/.zcompdump_flyline "$HOME"/.zcompdump* || true

# --- Warm crate caches -----------------------------------------------------
for repo in /agent/repos/flycomp /agent/repos/flyline-multishell; do
  if [ -f "$repo/Cargo.toml" ]; then
    cargo fetch --manifest-path "$repo/Cargo.toml"
    cargo build --manifest-path "$repo/Cargo.toml"
  fi
done
