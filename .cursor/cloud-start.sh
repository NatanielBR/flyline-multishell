#!/usr/bin/env bash
# Per-boot: snapshot install does not leave dockerd running.
set -euo pipefail

if docker info >/dev/null 2>&1; then
  if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock || true
  fi
  exit 0
fi

sudo dockerd --host=unix:///var/run/docker.sock >/tmp/dockerd.log 2>&1 &

ok=0
for _ in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 1
done

if [ "$ok" -ne 1 ]; then
  echo "dockerd failed to become ready; last log:" >&2
  tail -n 40 /tmp/dockerd.log >&2 || true
  exit 1
fi

if [ -S /var/run/docker.sock ]; then
  sudo chmod 666 /var/run/docker.sock || true
fi
