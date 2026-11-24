# systemd single static PID 1 binary in a container
# upstream recipe: https://github.com/systemd/systemd/pull/42820
# requires docker >= 28 on a cgroup v2 host
#
# build: docker build --target minimal -t systemd:minimal .
#        docker build --target noble   -t systemd:noble   .
# run:   ./run.sh [minimal|noble]
#
# minimal: FROM scratch, just the static binary plus machine-id and os-release,
#          boots to multi-user.target using the unit files embedded since v261
# noble:   ubuntu noble with the static binary as PID 1, gives a shell
#          and apt; the base image has no unit files so it also boots on the
#          embedded ones (apt install systemd adds the distro units)

FROM ubuntu:noble AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        gperf \
        libc6-dev \
        meson \
        pkg-config \
        python3-jinja2

# first commit that exits 0 on docker stop, not in any release yet (switch to
# a v263 tag once out): https://github.com/systemd/systemd/issues/44312
ADD https://github.com/systemd/systemd.git#2c70496761ed34fac36e7afa0adc0e63f9ff9409 /src
WORKDIR /src

RUN meson setup build-static \
        --buildtype=release \
        --default-library=static \
        --prefer-static \
        --auto-features=disabled \
        -Dbuild-static=true \
        -Dsystemd-multicall-binary=true \
    && ninja -C build-static systemd

FROM scratch AS minimal
COPY --from=builder /src/build-static/systemd /usr/lib/systemd/systemd
# empty, so systemd generates the machine ID at boot
COPY <<EOF /etc/machine-id
EOF
COPY <<EOF /usr/lib/os-release
ID=systemd-static
NAME=systemd
PRETTY_NAME="systemd (static single binary)"
EOF
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]

FROM ubuntu:noble AS noble
COPY --from=builder /src/build-static/systemd /usr/lib/systemd/systemd
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]
