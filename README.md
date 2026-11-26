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

`ghcr.io/felipecrs/passt`:

- `bin`: only the static binary of [passt](https://passt.top), which behaves as `pasta` if named as such

There are also images that build on these ones:

- [`ghcr.io/felipecrs/systemd-dind`](dind/README.md): with Docker, Compose, and Buildx

## Usage

```sh
docker run --rm -it \
  --tmpfs /run \
  --security-opt writable-cgroups=true \
  ghcr.io/felipecrs/systemd
```

Stop it with `docker stop`, and it will shut down in order and exit 0.

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

### To run it

- `--tmpfs /run`: systemd refuses to boot unless `/run` is a mount. It would mount it, but that takes `SYS_ADMIN`.
  - Running without it was [requested and closed](https://github.com/systemd/systemd/issues/8657) in 2018, and nothing seems to be open about it.
  - `VOLUME /run` in the image also makes it boot, but then it is not cleared on restart, [as it should](https://uapi-group.org/specifications/specs/linux_file_system_hierarchy/#run). For example, a PID file left there makes Docker fail to start in `systemd-dind:alpine` after the container is killed. It would also be on disk, and leave a volume behind for each container not run with `--rm`.
- `--security-opt writable-cgroups=true`: systemd creates a cgroup for each service, and Docker mounts them read-only.
  - The option was [added in Docker 28](https://github.com/moby/moby/pull/48828), instead of [making them writable by default](https://github.com/moby/moby/issues/42040). No newer version drops the need for it.
  - [moby/moby#46763](https://github.com/moby/moby/issues/46763) is open, about making them writable in private cgroup namespaces, which are the default.
- `-t`: systemd logs to `/dev/console`, which only exists with a TTY. It boots without it, but `docker logs` is empty.

No capabilities are needed, and it even boots with `--cap-drop ALL`. However, services using sandboxing options such as `ProtectSystem=` [may fail without `SYS_ADMIN`](https://github.com/systemd/systemd/issues/34565).

### In the image

- `STOPSIGNAL SIGRTMIN+3`: `docker stop` sends `SIGTERM` by default, on which systemd [reexecutes itself](https://www.freedesktop.org/software/systemd/man/latest/systemd.html#Signals) instead of shutting down. This is [the one systemd expects from container managers](https://systemd.io/CONTAINER_INTERFACE/).
  - Exiting 0 after that depends on [systemd/systemd#44312](https://github.com/systemd/systemd/issues/44312), which is not released yet.
- `/etc/machine-id`: if missing, every start is considered a first boot and gets a new ID, as keeping it takes `SYS_ADMIN`. It is empty so that each container generates its own.
- `/usr/lib/systemd/systemd`: the path that systemd reexecutes itself from.

## Development

See [AGENTS.md](AGENTS.md).
