# systemd single static PID 1 binary in a container
# upstream recipe: https://github.com/systemd/systemd/pull/42820
# cgroup v2 hosts only
#
# build: docker build --target minimal -t systemd:minimal .
#        docker build --target noble   -t systemd:noble   .
# run:   ./run.sh [minimal|noble] [--plain|--privileged]
#
# minimal: FROM scratch, just the static binary plus a tiny /etc, boots to
#          multi-user.target using the unit files embedded since v261
# noble:   ubuntu noble with the static binary as PID 1, gives a shell
#          and apt; the base image has no unit files so it also boots on the
#          embedded ones (apt install systemd adds the distro units)

ARG UBUNTU_VERSION=noble

FROM ubuntu:${UBUNTU_VERSION} AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        gperf \
        libcap-dev \
        libmount-dev \
        meson \
        ninja-build \
        pkg-config \
        python3 \
        python3-jinja2 \
    && rm -rf /var/lib/apt/lists/*

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

FROM ubuntu:${UBUNTU_VERSION} AS skeleton
RUN mkdir -p /rootfs/etc /rootfs/run /rootfs/tmp /rootfs/usr/lib /rootfs/var \
    && printf 'ID=systemd-static\nNAME=systemd\nPRETTY_NAME="systemd (static single binary)"\n' > /rootfs/usr/lib/os-release \
    && ln -s ../usr/lib/os-release /rootfs/etc/os-release \
    && : > /rootfs/etc/machine-id \
    && printf 'root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/usr/sbin/nologin\n' > /rootfs/etc/passwd \
    && printf 'root:x:0:\nnogroup:x:65534:\n' > /rootfs/etc/group \
    && chmod 1777 /rootfs/tmp

FROM scratch AS minimal
COPY --from=skeleton /rootfs/ /
COPY --from=builder /src/build-static/systemd /usr/lib/systemd/systemd
ENV container=docker
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]

FROM ubuntu:${UBUNTU_VERSION} AS noble
COPY --from=builder /src/build-static/systemd /usr/lib/systemd/systemd
ENV container=docker
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]