# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# check=error=true

# renovate: datasource=docker depName=docker
ARG DOCKER_VERSION=29.10.1

# replaced by bake with the one for each distro
FROM ghcr.io/felipecrs/systemd AS systemd

FROM systemd AS dind
# docker uses overlayfs, which cannot write on top of another one
VOLUME /var/lib/containerd /var/lib/docker

FROM dind AS debian
ADD --link --chmod=644 --checksum=sha256:1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570 https://download.docker.com/linux/debian/gpg /etc/apt/keyrings/docker.asc
ARG DOCKER_VERSION
RUN --mount=type=tmpfs,target=/var/lib/apt/lists <<-'EOF'
	set -eux
	export DEBIAN_FRONTEND=noninteractive

	# to fetch the packages below, and for docker to pull images
	apt-get update
	apt-get install -y --no-install-recommends ca-certificates

	. /etc/os-release
	cat >/etc/apt/sources.list.d/docker.sources <<-EOT
		Types: deb
		URIs: https://download.docker.com/linux/$ID
		Suites: $VERSION_CODENAME
		Components: stable
		Signed-By: /etc/apt/keyrings/docker.asc
	EOT

	apt-get update
	apt-get install -y --no-install-recommends \
		"docker-ce=5:$DOCKER_VERSION-*" \
		"docker-ce-cli=5:$DOCKER_VERSION-*" \
		docker-buildx-plugin \
		docker-compose-plugin \
		git \
		openssh-client \
		pigz \
		procps \
		xz-utils
EOF

FROM debian AS ubuntu

# docker has no repository for alpine, so use the official image
FROM docker:${DOCKER_VERSION}-dind AS docker

FROM dind AS alpine
RUN <<-'EOF'
	set -eux
	apk add --no-cache \
		git \
		iptables \
		openssh-client \
		pigz \
		xz
	addgroup -S docker
	mkdir -p /etc/systemd/system/multi-user.target.wants
	ln -s ../docker.service /etc/systemd/system/multi-user.target.wants/
EOF
COPY --link --from=docker \
    /usr/local/bin/containerd-shim-runc-v2 \
    /usr/local/bin/docker \
    /usr/local/bin/docker-init \
    /usr/local/bin/docker-proxy \
    /usr/local/bin/dockerd \
    /usr/local/bin/runc \
    /usr/local/bin/
COPY --link --from=docker \
    /usr/local/libexec/docker/cli-plugins/docker-buildx \
    /usr/local/libexec/docker/cli-plugins/docker-compose \
    /usr/local/libexec/docker/cli-plugins/
COPY --link <<-'EOF' /etc/systemd/system/docker.service
	[Unit]
	Description=Docker Application Container Engine

	[Service]
	Type=notify
	# systemd leaves /bin and /sbin out, but alpine still has commands there
	Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	ExecStart=/usr/local/bin/dockerd
	Restart=always
	RestartSec=2
	Delegate=yes
	KillMode=process
EOF
