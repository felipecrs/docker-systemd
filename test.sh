#!/usr/bin/env bash
# checks that every variant boots and then exits 0 on docker stop

set -euo pipefail

cd "$(dirname "$0")"

tags="$(docker buildx bake --print image | jq -r '.target[].tags[0] | sub(".*:"; "")')"

failed=no
for tag in $tags; do
  container="$(./run.sh "$tag" --detach)"
  booted=no
  for _ in {1..30}; do
    if docker logs "$container" 2>&1 | grep -q 'Startup finished'; then
      booted=yes
      break
    fi
    sleep 1
  done
  # the container is removed once stopped, so get the exit code by waiting
  exec 3< <(docker wait "$container")
  sleep 1
  docker stop "$container" >/dev/null
  code="$(cat <&3)"
  echo "$tag: booted=$booted exit=$code"
  [[ "$booted" == yes && "$code" == 0 ]] || failed=yes
done

[[ "$failed" == no ]]
