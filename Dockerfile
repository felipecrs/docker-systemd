# syntax=docker/dockerfile:1.29
# check=error=true

# first commit that exits 0 on docker stop, not in any release yet (switch to
# a v263 tag once out): https://github.com/systemd/systemd/issues/44312
ARG SYSTEMD_REVISION=2c70496761ed34fac36e7afa0adc0e63f9ff9409
# time of the commit above, so that the build is reproducible (it could be set
# to "source" instead, but that makes every build fetch the whole git history)
ARG SOURCE_DATE_EPOCH=1795452022

FROM scratch AS source
ARG SYSTEMD_REVISION
ADD https://github.com/systemd/systemd.git?ref=${SYSTEMD_REVISION}&fetch-by-commit=true /

# upstream recipe: https://github.com/systemd/systemd/pull/42820
FROM ubuntu:26.04 AS build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends \
    gcc \
    gperf \
    libc6-dev \
    meson \
    pkg-config \
    python3-jinja2
EOF
# systemd embeds it in the binary
ARG SOURCE_DATE_EPOCH
RUN --network=none --mount=type=bind,from=source,target=/src <<EOF
set -eux
meson setup /build /src \
    --buildtype=release \
    --default-library=static \
    --prefer-static \
    --auto-features=disabled \
    -Dbuild-static=true \
    -Dsystemd-multicall-binary=true
ninja -C /build systemd
EOF

# just the static binary, to be copied into other images
FROM scratch AS bin
COPY --link --from=build /build/systemd /systemd

# overridden by the variants in docker-bake.hcl
FROM ubuntu:26.04 AS base

FROM base AS image
COPY --link --from=bin /systemd /usr/lib/systemd/systemd
# empty, so that systemd generates the machine ID at boot
COPY --link <<EOF /etc/machine-id
EOF
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]
