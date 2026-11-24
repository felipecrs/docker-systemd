# docker-systemd

[systemd](https://github.com/systemd/systemd) as a single static binary, to use as PID 1 in containers. No unit files are needed, as the binary embeds a basic set of them.

Requires Docker >= 28 on a cgroup v2 host. Available for `linux/amd64` and `linux/arm64`.

## Images

Tags follow the ones of the [Docker Official Images](https://hub.docker.com/_/docker).

`ghcr.io/felipecrs/systemd`:

- `latest`, `trixie`, `bookworm`: Debian with systemd as PID 1
- `resolute`, `noble`, `jammy`: Ubuntu with systemd as PID 1
- `alpine`, `alpine3.24`, `alpine3.23`, `alpine3.22`: Alpine with systemd as PID 1
- `bin`: only the static binary

`ghcr.io/felipecrs/systemd-dind`, which is any of the above with Docker, Compose, and Buildx:

- `latest`, `29`, `29.10`, `29.10.0`: the default, on Debian
- `noble`, `29-noble`, `29.10-noble`, `29.10.0-noble`, and so on: on a given distro

## Usage

```sh
docker run --rm -it \
  --tmpfs /run \
  --security-opt writable-cgroups=true \
  ghcr.io/felipecrs/systemd
```

Stop it with `docker stop`, and it will shut down in order and exit 0.

### Docker in Docker

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

### Using your own base image

```Dockerfile
FROM debian
COPY --link --from=ghcr.io/felipecrs/systemd:bin /systemd /usr/lib/systemd/systemd
COPY --link <<EOF /etc/machine-id
EOF
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]
```

If your image also installs the systemd package from the distro, copy the binary after it, as the package replaces `/usr/lib/systemd/systemd`.

## Why is each of these needed?

### To run systemd

- `--tmpfs /run`: systemd refuses to boot unless `/run` is a mount. It would mount it, but that takes `SYS_ADMIN`.
  - Running without it was [requested and closed](https://github.com/systemd/systemd/issues/8657) in 2018, and I found nothing open about it.
  - `VOLUME /run` in the image also makes it boot, but then it is not cleared on restart, [as it should](https://uapi-group.org/specifications/specs/linux_file_system_hierarchy/#run). For example, a PID file left there makes Docker fail to start in `systemd-dind:alpine` after the container is killed. It would also be on disk, and leave a volume behind for each container not run with `--rm`.
- `--security-opt writable-cgroups=true`: systemd creates a cgroup for each service, and Docker mounts them read-only.
  - The option was [added in Docker 28](https://github.com/moby/moby/pull/48828), instead of [making them writable by default](https://github.com/moby/moby/issues/42040). No newer version drops the need for it.
  - [moby/moby#46763](https://github.com/moby/moby/issues/46763) is open, about making them writable in private cgroup namespaces, which are the default.
- `-t`: systemd logs to `/dev/console`, which only exists with a TTY. It boots without it, but `docker logs` is empty.

No capabilities are needed, and it even boots with `--cap-drop ALL`. However, services using sandboxing options such as `ProtectSystem=` [may fail without `SYS_ADMIN`](https://github.com/systemd/systemd/issues/34565).

### To run dind

All of the above, and also:

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

### In the images

- `STOPSIGNAL SIGRTMIN+3`: `docker stop` sends `SIGTERM` by default, on which systemd [reexecutes itself](https://www.freedesktop.org/software/systemd/man/latest/systemd.html#Signals) instead of shutting down. This is [the one systemd expects from container managers](https://systemd.io/CONTAINER_INTERFACE/).
  - Exiting 0 after that depends on [systemd/systemd#44312](https://github.com/systemd/systemd/issues/44312), which is not released yet.
- `/etc/machine-id`: if missing, every start is considered a first boot and gets a new ID, as keeping it takes `SYS_ADMIN`. It is empty so that each container generates its own.
- `/usr/lib/systemd/systemd`: the path that systemd reexecutes itself from.
- `VOLUME` in dind: Docker stores images with overlayfs, which cannot write on top of another one, such as the one of the container.

## Development

Install [mise](https://mise.jdx.dev), then:

```sh
mise run build             # build everything
mise run build dind-noble  # build a single target
mise run test              # test all variants
mise run lint              # check everything
mise run fix               # fix everything that can be fixed
hk install --mise          # optional, do it on every commit
mise tasks                 # list all tasks
```

To add another kind of image, such as dind, create a directory with a `Dockerfile` that starts from the `systemd` context, and a target for it in `docker-bake.hcl`.

The [ci workflow](.github/workflows/ci.yaml) publishes the images from `main`, once all tests pass.
