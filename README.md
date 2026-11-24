# docker-systemd

[systemd](https://github.com/systemd/systemd) as a single static binary, to use as PID 1 in containers. No unit files are needed, as the binary embeds a basic set of them.

Requires Docker >= 28 on a cgroup v2 host. Available for `linux/amd64` and `linux/arm64`.

## Images

- `latest`, `trixie`, `bookworm`: Debian with systemd as PID 1
- `resolute`, `noble`, `jammy`: Ubuntu with systemd as PID 1
- `alpine`, `alpine3.24`, `alpine3.23`, `alpine3.22`: Alpine with systemd as PID 1
- `bin`: only the static binary

## Usage

```sh
docker run --rm -it \
  --tmpfs /run:exec --tmpfs /run/lock:exec --tmpfs /tmp:exec \
  --security-opt writable-cgroups=true \
  ghcr.io/felipecrs/systemd
```

Stop it with `docker stop`, and it will shut down in order and exit 0.

### Using your own base image

```Dockerfile
FROM debian
COPY --link --from=ghcr.io/felipecrs/systemd:bin /systemd /usr/lib/systemd/systemd
# only needed if the base image does not have it already
COPY --link <<EOF /etc/machine-id
EOF
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]
```

If your image also installs the systemd package from the distro, copy the binary after it, as the package replaces `/usr/lib/systemd/systemd`.

## Development

```sh
docker buildx bake --list=targets # list what can be built
docker buildx bake                # build everything
docker buildx bake check          # lint the Dockerfile
./run.sh alpine                   # run a variant
./test.sh                         # check that all variants boot and exit 0
```

The [ci workflow](.github/workflows/ci.yaml) publishes the images from `main`, once all tests pass.
