#!/usr/bin/env bash
# runs a variant, which is pulled if not built before
#
# usage:
#   ./run.sh [tag] [docker run options...]
#
# requires docker >= 28 on a cgroup v2 host

set -euo pipefail

exec docker run --rm -it \
  --tmpfs /run:exec --tmpfs /run/lock:exec --tmpfs /tmp:exec \
  --security-opt writable-cgroups=true \
  "${@:2}" \
  "ghcr.io/felipecrs/systemd:${1:-latest}"
