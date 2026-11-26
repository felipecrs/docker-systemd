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
  --device /dev/net/tun \
  --mount type=bind,source=/sys,target=/mnt/sys,bind-recursive=disabled \
  --security-opt apparmor=rootlesskit \
  --security-opt seccomp=unconfined \
  --security-opt systempaths=unconfined \
  --stop-timeout 30 \
  ghcr.io/felipecrs/systemd-dind
```

It needs neither `--privileged` nor any capability besides the default ones, as Docker runs in its own [user namespace](https://man7.org/linux/man-pages/man7/user_namespaces.7.html). However, root in it can still change settings of the host, such as the ones in `/proc/sys`, so do not run anything you do not trust in it.

Because of that, Docker also has its own network:

- Ports that are published are reachable from the container, and from outside of it, a moment after they are opened.
- The IP addresses of the containers inside are not reachable from the container, only from each other.

## Why is each of these needed?

### To run it

Everything [needed to run systemd](../README.md#to-run-it), and also:

- `--device /dev/net/tun`: [pasta](https://passt.top) connects the network of Docker to the one of the container through it.
- `--mount type=bind,source=/sys,target=/mnt/sys,bind-recursive=disabled`: only needed to run containers with `--privileged` in it, such as the ones of the `docker-container` driver of Buildx.
  - They mount a writable `/sys`, but Docker mounts the one here as read-only, and the kernel [does not allow a user namespace to get around that](https://github.com/torvalds/linux/blob/v6.18/fs/namespace.c#L6120) unless a writable one is also visible.
  - It cannot replace `/sys`, as systemd does not start. `bind-recursive=disabled` leaves out what is mounted under it, such as the cgroups of the host.
- `--security-opt seccomp=unconfined`: the [default profile](https://docs.docker.com/engine/security/seccomp/) blocks creating user namespaces without `SYS_ADMIN`. It also blocks `keyctl` and `pivot_root`, which runc uses to start each container.
  - Allowing `keyctl` was [proposed and closed](https://github.com/moby/profiles/pull/2), as the kernel keyring is not namespaced. runc only [tolerates its absence, not its denial](https://github.com/opencontainers/runc/blob/v1.4.0/libcontainer/standard_init_linux.go).
  - [opencontainers/runtime-spec#1112](https://github.com/opencontainers/runtime-spec/pull/1112) is open, and would let Docker ask runc not to use it. `pivot_root` would still be blocked.
- `--security-opt apparmor=rootlesskit`: the [default profile](https://github.com/moby/profiles/blob/main/apparmor/template.go) blocks `mount`. It has no effect if the host does not use AppArmor.
  - `unconfined` is not enough on Ubuntu, which [restricts user namespaces](https://documentation.ubuntu.com/security/security-features/privilege-restriction/apparmor/) unless a profile allows them. This one, which comes with Ubuntu, does nothing besides that.
  - If the host uses AppArmor but does not have this profile, use `apparmor=unconfined` instead.
- `--security-opt systempaths=unconfined`: Docker disables IPv6 in the containers that do not use it through `/proc/sys`, which is otherwise read-only.
  - Docker 26.1 had [a variable to skip it](https://github.com/moby/moby/pull/47769), but it was [removed in Docker 27](https://github.com/moby/moby/pull/47963).
  - Enabling IPv6 in all networks instead, as suggested there, does not work either, as the daemon does not start.
- `--stop-timeout 30`: Docker waits 10 seconds for a container to stop before killing it, so the one inside needs more time than that to do the same with its own containers.

The [dind script](https://github.com/moby/moby/blob/master/hack/dind) from moby is not used because it does not help to drop any of these, and systemd already does the part about cgroups.

Docker has [an open request](https://github.com/docker-library/docker/issues/306) for official dind images based on other distros, and an option in between these and `--privileged` was [proposed and closed](https://github.com/moby/moby/pull/39702).

### In the image

- `VOLUME`: Docker stores images with overlayfs, which cannot write on top of another one, such as the one of the container.
  - On Debian and Ubuntu, containerd is a separate service by default, and stores images in `/var/lib/containerd`. It is disabled, so that Docker runs containerd by itself, with everything in a single volume and in the same namespaces.
- `docker.service`: [`PrivateUsers=full`](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#PrivateUsers=) creates the user namespace, in which Docker has all capabilities, but only over the namespaces created from it. `identity` would be enough, but it denies `setgroups`, which many images use to drop privileges.
  - systemd can also create the other namespaces, with `PrivateNetwork=` and `DelegateNamespaces=`, but fails to set up the mount one without `SYS_ADMIN`, so `unshare` does it.
  - Rootless Docker is not used because it needs [a systemd user session to limit the resources of containers](https://docs.docker.com/engine/security/rootless/tips/#limiting-resources). That needs D-Bus and the systemd package of the distro, which would replace the binary of this image, and does not exist on Alpine.
- `pasta`: connects the network of Docker, and forwards its ports. Built [from source](../passt/Dockerfile), as the packages of older distros are either too old or missing.
- `ca-certificates`: to pull images.
- `git`: to build from Git repositories, and to `ADD` them.
- `iptables`: to create firewall rules. The packages for Debian and Ubuntu already depend on it.
- `openssh-client`: to do the same as `git` with repositories over SSH, and to connect to other Docker hosts over SSH.
- `pigz`: to decompress images. It is barely faster than without it (up to 7% when tested), but it is tiny, and recommended by Docker.
- `procps`: provides the `ps` used by `docker top`. Alpine already has one.
- `xz`: to `ADD` and import `.tar.xz` files.
