#!/usr/bin/env bash
# builds and runs the systemd 262 static PID 1 containers
#
# usage:
#   ./run.sh                 build if needed and run the minimal target
#   ./run.sh noble           run the ubuntu noble based target
#   ./run.sh --plain         no cgroup mounts, tests the degraded boot path
#   ./run.sh --privileged    fallback for hosts where the unprivileged flags fail
#
# note: docker stop triggers the orderly systemd shutdown, but the final
# kernel halt is denied inside docker, so the container exits 255 (harmless)
#
# requires a cgroup v2 host

set -euo pipefail

target="minimal"
extra=()
cgroup=(--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw)

for arg in "$@"; do
  case "$arg" in
    minimal|noble) target="$arg" ;;
    --plain) cgroup=() ;;
    --privileged) extra+=(--privileged) ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

version="$(docker info --format '{{.CgroupVersion}}' 2>/dev/null || true)"
if [ "${version:-}" != "2" ]; then
  echo "this setup targets cgroup v2 hosts only, docker reports cgroup version: '${version:-unknown}'" >&2
  exit 1
fi

image="systemd262:${target}"
docker image inspect "$image" >/dev/null 2>&1 || docker build --target "$target" -t "$image" .

exec docker run --rm -it \
  --tmpfs /run:exec --tmpfs /run/lock:exec --tmpfs /tmp:exec \
  ${cgroup[@]+"${cgroup[@]}"} \
  ${extra[@]+"${extra[@]}"} \
  "$image"