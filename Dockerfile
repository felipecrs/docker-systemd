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
FROM debian:trixie@sha256:3cda3ca472ce45507a5109c6a3907093e24d9ae67d55954c9a07a45665dafba2 AS trixie
FROM debian:bookworm@sha256:1d04200c2ece1d4d75a2a6f8e11ebce7d86a2ae28b34bb2c9cbb3ee9f4953e75 AS bookworm
FROM ubuntu:resolute@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db AS resolute
FROM ubuntu:noble@sha256:562111b88caa79c71391c0c4d3c2114a7d5c35915c20561fd893cb1e07929e6b AS noble
FROM ubuntu:jammy@sha256:b000e69a50ff940390233025e7a337fb8469b509e2334fa4d018ac30f3e18cdb AS jammy
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS alpine3.24
FROM alpine:3.23@sha256:469c9ea410b9215eaee7976ba6c0639039b444be8e5d638f7abbada189971eb2 AS alpine3.23
FROM alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f AS alpine3.22

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
