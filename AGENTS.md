# AI Agent Developer Guide: `flyline`

This document provides a simplified developer guide for [flyline](.), a Bash plugin replacing standard GNU readline with a modern, Rust-based line editor.

## Key Files
- **[src/lib.rs](src/lib.rs)**: C FFI bindings loaded directly into the host Bash process (e.g. `flyline_get_char`).
- **[src/app/mod.rs](src/app/mod.rs)**: The main TUI application loop, redraw coordination, and frame rendering.
- **[src/app/actions.rs](src/app/actions.rs)**: Handles keystrokes, keybindings, modes, and command actions.
- **[src/bash_funcs.rs](src/bash_funcs.rs)**: Bridges Rust code with the host Bash shell (variable retrieval, path resolution, and calling Bash functions/hooks).
- **[src/bash_symbols.rs](src/bash_symbols.rs)**: C-compatible definitions of GNU Bash internal types, structures, and global variables.
- **[src/prompt_manager.rs](src/prompt_manager.rs)**: Asynchronous shell prompt widgets, PS1 configurations, and terminal animations.
- **[src/text_buffer.rs](src/text_buffer.rs)**: Text state management, cursor movements, and undo/redo stacks.

## Useful Commands
```bash
# Build the loadable builtin library (target/debug/libflyline.so)
cargo build

# Load the plugin in the current Bash session
enable -f target/debug/libflyline.so flyline

# Unload the plugin and restore default readline
enable -d flyline

# Run unit tests only (avoids slow different-bash-version integration tests)
cargo test --lib

# To run flycomp unit tests specifically
cargo test -p flycomp

# Format the codebase after making changes
cargo fmt
```

> [!TIP]
> Avoid running the full `cargo test` suite locally. The integration tests (`tests/docker_integration_tests.rs`) spawn Docker containers testing multiple versions of Bash, which is extremely slow. Prefer running `cargo test --lib` or testing specific packages.

## Cursor Cloud specific instructions

### Docker in this environment
Cloud Agents run Docker inside another container. For bake/integration tests (`docker buildx bake …`), configure the daemon with **fuse-overlayfs** and **iptables-legacy** before starting it — plain `overlayfs`/`vfs` often fails with `invalid argument` on BuildKit mounts. See [Running Docker](https://cursor.com/docs/cloud-agent/setup#running-docker).

```bash
sudo apt-get install -y fuse-overlayfs iptables docker.io docker-buildx
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
printf '%s\n' '{' '  "storage-driver": "fuse-overlayfs"' '}' | sudo tee /etc/docker/daemon.json
sudo dockerd --host=unix:///var/run/docker.sock &
# or: sudo service docker start  (once the daemon.json is in place)
sudo chmod 666 /var/run/docker.sock   # if the agent user is not in group docker yet
```

### Fish / zsh local smoke
```bash
cargo build --release --features standalone
sh install.sh --local target/release
docker buildx bake -f docker-bake.hcl fish-integration-test
docker buildx bake -f docker-bake.hcl zsh-integration-test
```

