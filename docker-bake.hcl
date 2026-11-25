variable "IMAGE" {
  description = "Image repository to tag, dind goes in the one suffixed with -dind"
  type        = string
  default     = "ghcr.io/felipecrs/systemd"
}

variable "PLATFORMS" {
  description = "Platforms to build for, defaults to the local one"
  type        = list(string)
  default     = []
}

variable "SYSTEMD_REVISION" {
  description = "systemd commit to build, defaults to the one in the Dockerfile"
  type        = string
  default     = null
  validation {
    condition     = SYSTEMD_REVISION == null ? true : can(regex("^[0-9a-f]{40}$", SYSTEMD_REVISION))
    error_message = "SYSTEMD_REVISION must be a full commit SHA."
  }
}

variable "VARIANTS" {
  description = "Distros and their tags, the first being the stage in the Dockerfile"
  type        = list(object({ distro = string, tags = list(string) }))
  default = [
    { distro = "debian", tags = ["trixie", "latest"] },
    { distro = "debian", tags = ["bookworm"] },
    { distro = "ubuntu", tags = ["resolute"] },
    { distro = "ubuntu", tags = ["noble"] },
    { distro = "ubuntu", tags = ["jammy"] },
    { distro = "alpine", tags = ["alpine3.24", "alpine"] },
    { distro = "alpine", tags = ["alpine3.23"] },
    { distro = "alpine", tags = ["alpine3.22"] },
  ]
}

variable "DOCKER_VERSIONS" {
  description = "Versions of docker for dind, the first also gets the unversioned tags"
  type        = list(string)
  # renovate: datasource=docker depName=docker
  default = ["29.10.1"]
}

# as in the docker official images, such as 29.10.0-trixie, 29, and trixie
function "dind_tags" {
  params = [version, tags]
  result = flatten([
    for prefix in concat(
      [version, regex("^[0-9]+[.][0-9]+", version), split(".", version)[0]],
      version == DOCKER_VERSIONS[0] ? [""] : [],
    ) : [
      for tag in tags : join("-", compact([prefix, tag == "latest" && prefix != "" ? "" : tag]))
    ]
  ])
}

function "metadata" {
  params = [title]
  result = {
    "org.opencontainers.image.source" = "https://github.com/felipecrs/docker-systemd"
    "org.opencontainers.image.title"  = title
  }
}

group "default" {
  targets = ["bin", "images"]
}

# everything that is tested
group "images" {
  targets = ["image", "dind"]
}

target "_common" {
  args = {
    SYSTEMD_REVISION = SYSTEMD_REVISION
  }
  platforms = PLATFORMS
  policy    = [{ filename = "policy.rego" }]
}

target "bin" {
  description = "Only the static binary"
  inherits    = ["_common"]
  target      = "bin"
  tags        = ["${IMAGE}:bin"]
  labels      = metadata("systemd")
  annotations = [for k, v in metadata("systemd") : "index,manifest:${k}=${v}"]
}

target "image" {
  matrix = {
    variant = VARIANTS
  }
  name        = replace(variant.tags[0], ".", "-")
  description = "systemd on ${variant.tags[0]}"
  inherits    = ["_common"]
  target      = "image"
  args = {
    VARIANT = variant.tags[0]
  }
  tags        = [for tag in variant.tags : "${IMAGE}:${tag}"]
  labels      = metadata("systemd on ${variant.tags[0]}")
  annotations = [for k, v in metadata("systemd on ${variant.tags[0]}") : "index,manifest:${k}=${v}"]
}

target "dind" {
  matrix = {
    variant = VARIANTS
    version = DOCKER_VERSIONS
  }
  name        = replace("dind-${version}-${variant.tags[0]}", ".", "-")
  description = "systemd and docker ${version} on ${variant.tags[0]}"
  inherits    = ["_common"]
  dockerfile  = "dind/Dockerfile"
  target      = variant.distro
  contexts = {
    systemd = "target:${replace(variant.tags[0], ".", "-")}"
  }
  args = {
    DOCKER_VERSION = version
  }
  tags        = [for tag in dind_tags(version, variant.tags) : "${IMAGE}-dind:${tag}"]
  labels      = metadata("systemd and docker ${version} on ${variant.tags[0]}")
  annotations = [for k, v in metadata("systemd and docker ${version} on ${variant.tags[0]}") : "index,manifest:${k}=${v}"]
}

target "check" {
  matrix = {
    dockerfile = ["Dockerfile", "dind/Dockerfile"]
  }
  name        = "check-${replace(dockerfile, "/", "-")}"
  description = "Lint ${dockerfile}"
  dockerfile  = dockerfile
  call        = "check"
}
