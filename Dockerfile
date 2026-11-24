# syntax=ghcr.io/felipecrs/dockerfile:557987808
# check=error=true

# TODO: switch back to docker/dockerfile once these are released:
# https://github.com/moby/buildkit/pull/7386
# https://github.com/moby/buildkit/pull/7463

# TODO: switch to a v263 tag once this is released:
# https://github.com/systemd/systemd/issues/44312
ARG SYSTEMD_REVISION=2c70496761ed34fac36e7afa0adc0e63f9ff9409
# use the commit time of the source, so that the build is reproducible
ARG SOURCE_DATE_EPOCH=source

# which of the stages below to use as base
ARG VARIANT=trixie
FROM debian:trixie AS trixie
FROM debian:bookworm AS bookworm
FROM ubuntu:resolute AS resolute
FROM ubuntu:noble AS noble
FROM ubuntu:jammy AS jammy
FROM alpine:3.24 AS alpine3.24
FROM alpine:3.23 AS alpine3.23
FROM alpine:3.22 AS alpine3.22

FROM scratch AS source
ARG SYSTEMD_REVISION
ADD https://github.com/systemd/systemd.git?ref=${SYSTEMD_REVISION}&fetch-by-commit=true&mtime=commit /

# upstream recipe: https://github.com/systemd/systemd/pull/42820
FROM resolute AS build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<-'EOF'
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
RUN --network=none --mount=type=bind,from=source,target=/src <<-'EOF'
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

FROM ${VARIANT} AS base

FROM base AS image
# where systemd expects itself to be, to reexecute
COPY --link --from=bin /systemd /usr/lib/systemd/systemd
# debian and alpine do not have it, and without it every start is a first boot
# with a new machine ID; it is empty so that each container generates its own
COPY --link <<-'EOF' /etc/machine-id
EOF
# systemd reexecutes itself on SIGTERM, which is the default
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/lib/systemd/systemd"]
