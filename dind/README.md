# systemd-dind

Docker in Docker, with [systemd](../README.md) as PID 1. Includes Compose and Buildx.

## Tags

- `latest`, `29`, `29.10`, `29.10.0`: the default, on Debian
- `noble`, `29-noble`, `29.10-noble`, `29.10.0-noble`, and so on: on a given distro

## Usage

```sh
docker run --rm -it \
  --tmpfs /run \
  --security-opt writable-cgroups=true \
  --cap-add NET_ADMIN \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --security-opt seccomp=unconfined \
  --security-opt systempaths=unconfined \
  --stop-timeout 30 \
  ghcr.io/felipecrs/systemd-dind
```

It does not need `--privileged`, but these are still broad permissions, so do not run anything you do not trust in it.

## Why is each of these needed?

### To run it

Everything [needed to run systemd](../README.md#to-run-it), and also:

- `--cap-add NET_ADMIN`: Docker creates bridges and firewall rules.
- `--cap-add SYS_ADMIN`: Docker mounts the file systems of the containers, and creates their namespaces.
- `--security-opt seccomp=unconfined`: the [default profile](https://docs.docker.com/engine/security/seccomp/) blocks `keyctl` and `pivot_root`, which runc uses to start each container.
  - Allowing `keyctl` was [proposed and closed](https://github.com/moby/profiles/pull/2), as the kernel keyring is not namespaced. runc only [tolerates its absence, not its denial](https://github.com/opencontainers/runc/blob/v1.4.0/libcontainer/standard_init_linux.go).
  - [opencontainers/runtime-spec#1112](https://github.com/opencontainers/runtime-spec/pull/1112) is open, and would let Docker ask runc not to use it. `pivot_root` would still be blocked.
- `--security-opt apparmor=unconfined`: the [default profile](https://github.com/moby/profiles/blob/main/apparmor/template.go) blocks `mount`, regardless of `SYS_ADMIN`. It has no effect if the host does not use AppArmor.
- `--security-opt systempaths=unconfined`: Docker disables IPv6 in the containers that do not use it through `/proc/sys`, which is otherwise read-only.
  - Docker 26.1 had [a variable to skip it](https://github.com/moby/moby/pull/47769), but it was [removed in Docker 27](https://github.com/moby/moby/pull/47963).
  - Enabling IPv6 in all networks instead, as suggested there, does not work either, as the daemon does not start.
- `--stop-timeout 30`: Docker waits 10 seconds for a container to stop before killing it, so the one inside needs more time than that to do the same with its own containers.

The [dind script](https://github.com/moby/moby/blob/master/hack/dind) from moby is not used because it does not help to drop any of these, and systemd already does the part about cgroups.

Docker has [an open request](https://github.com/docker-library/docker/issues/306) for official dind images based on other distros, and an option in between these and `--privileged` was [proposed and closed](https://github.com/moby/moby/pull/39702).

### In the image

- `VOLUME`: Docker stores images with overlayfs, which cannot write on top of another one, such as the one of the container.
- `ca-certificates`: to pull images.
- `git`: to build from Git repositories, and to `ADD` them.
- `iptables`: to create firewall rules. The packages for Debian and Ubuntu already depend on it.
- `openssh-client`: to do the same as `git` with repositories over SSH, and to connect to other Docker hosts over SSH.
- `pigz`: to decompress images. It is barely faster than without it (up to 7% when tested), but it is tiny, and recommended by Docker.
- `procps`: provides the `ps` used by `docker top`. Alpine already has one.
- `xz`: to `ADD` and import `.tar.xz` files.
