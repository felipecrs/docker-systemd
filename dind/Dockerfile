# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# check=error=true

# renovate: datasource=docker depName=docker
ARG DOCKER_VERSION=29.10.1

# both replaced by bake, the first with the one for each distro
FROM ghcr.io/felipecrs/systemd AS systemd
FROM scratch AS passt

FROM systemd AS dind
# docker uses overlayfs, which cannot write on top of another one
VOLUME /var/lib/docker
# behaves as pasta because of its name
COPY --link --from=passt /passt /usr/local/bin/pasta
# the same service for all distros
RUN <<-'EOF'
	set -eux
	mkdir -p /etc/systemd/system/multi-user.target.wants
	cd /etc/systemd/system
	ln -s ../docker.service multi-user.target.wants/
	# docker runs containerd by itself, and creates the socket too
	ln -s /dev/null containerd.service
	ln -s /dev/null docker.socket
EOF
COPY --link <<-'EOF' /etc/systemd/system/docker.service
	[Unit]
	Description=Docker Application Container Engine

	[Service]
	Type=notify
	# systemd leaves /bin and /sbin out, but alpine still has commands there
	Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	# gives it all capabilities, but only over the namespaces created below
	PrivateUsers=full
	# pasta has to start first, so that docker does not pick the same subnet
	ExecStart=/usr/bin/unshare --mount /bin/sh -euxc '\
		touch /run/docker-netns; \
		unshare --net=/run/docker-netns true; \
		pasta --config-net --netns-only --runas 0 --no-map-gw \
			--tcp-ports auto --udp-ports auto --tcp-ns none --udp-ns none \
			--netns /run/docker-netns; \
		exec nsenter --net=/run/docker-netns dockerd'
	Restart=always
	RestartSec=2
	Delegate=yes
	# also stops pasta and the containers, as their network is gone
	KillMode=mixed
EOF

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
