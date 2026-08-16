#!/usr/bin/env bash
# Per-boot: snapshot install does not leave dockerd running.
# The agent user is typically not in group `docker`, so chmod the socket
# *before* probing `docker info` — otherwise a healthy daemon looks down
# and a second dockerd fails on /var/run/docker.pid.
set -euo pipefail

fix_sock() {
  if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock || true
  fi
}

fix_sock
if docker info >/dev/null 2>&1; then
  exit 0
fi

if [ -f /var/run/docker.pid ]; then
  pid=$(cat /var/run/docker.pid 2>/dev/null || true)
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    fix_sock
    if docker info >/dev/null 2>&1; then
      exit 0
    fi
    echo "dockerd pid $pid is running but docker info still fails" >&2
    exit 1
  fi
fi

sudo dockerd --host=unix:///var/run/docker.sock >/tmp/dockerd.log 2>&1 &

ok=0
for _ in $(seq 1 30); do
  fix_sock
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
