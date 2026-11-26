# restricts the sources of the build
package docker

default allow := false

allow if input.local

# this repository, as used by ci instead of a local directory
allow if input.git.remote == "https://github.com/felipecrs/docker-systemd.git"

allow if {
  input.image.host == "docker.io"
  input.image.repo in {"alpine", "debian", "docker", "ubuntu", "docker/buildkit-syft-scanner", "docker/dockerfile"}
}

allow if input.image.fullRepo == "ghcr.io/felipecrs/dockerfile"

allow if input.http.url == "https://download.docker.com/linux/debian/gpg"

# the bin images, as used by the variants in ci
allow if {
  input.image.fullRepo in {"ghcr.io/felipecrs/passt", "ghcr.io/felipecrs/systemd"}
  input.image.isCanonical
}

allow if {
  input.git.remote in {"https://github.com/systemd/systemd.git", "https://passt.top/passt/.git"}
  input.git.isCommitRef
}

decision := {"allow": allow}
