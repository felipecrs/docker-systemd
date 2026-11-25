# syntax=ghcr.io/felipecrs/dockerfile:557987808
# check=error=true

# TODO: switch back to docker/dockerfile once these are released:
# https://github.com/moby/buildkit/pull/7386
# https://github.com/moby/buildkit/pull/7463

# 2026_10_02.cba3570
ARG PASST_REVISION=cba357068dc586e7540971eb40bb56c5e62c4de1
# use the commit time of the source, so that the build is reproducible
ARG SOURCE_DATE_EPOCH=source

FROM scratch AS source
ARG PASST_REVISION
# the trailing .git is what makes it a git repository for buildkit
ADD https://passt.top/passt/.git?ref=${PASST_REVISION}&fetch-by-commit=true&mtime=commit /

FROM ubuntu:resolute@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db AS build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<-'EOF'
	set -eux
	apt-get update
	apt-get install -y --no-install-recommends \
		gcc \
		libc6-dev \
		make
EOF
COPY --link --from=source / /src
ARG PASST_REVISION
RUN --network=none <<-'EOF'
	set -eux
	make -C /src static VERSION="$PASST_REVISION"
	strip /src/passt
EOF

# just the static binary, to be copied into other images
FROM scratch AS bin
COPY --link --from=build /src/passt /passt
