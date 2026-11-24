#!/usr/bin/env bash
# builds and runs the systemd static PID 1 containers
#
# usage:
#   ./run.sh                 build if needed and run the minimal target
#   ./run.sh noble           run the ubuntu noble based target
#
# requires docker >= 28 on a cgroup v2 host

set -euo pipefail

target="${1:-minimal}"

image="systemd:${target}"
docker image inspect "$image" >/dev/null 2>&1 || docker build --target "$target" -t "$image" .

exec docker run --rm -it \
  --tmpfs /run:exec --tmpfs /run/lock:exec --tmpfs /tmp:exec \
  --security-opt writable-cgroups=true \
  "$image"
