variable "IMAGE" {
  description = "Image repository to tag"
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
  description = "Base images and their tags, which follow the Docker Official Images"
  type        = list(object({ base = string, tags = list(string) }))
  default = [
    { base = "debian:trixie", tags = ["trixie", "latest"] },
    { base = "debian:bookworm", tags = ["bookworm"] },
    { base = "ubuntu:resolute", tags = ["resolute"] },
    { base = "ubuntu:noble", tags = ["noble"] },
    { base = "ubuntu:jammy", tags = ["jammy"] },
    { base = "alpine:3.24", tags = ["alpine3.24", "alpine"] },
    { base = "alpine:3.23", tags = ["alpine3.23"] },
    { base = "alpine:3.22", tags = ["alpine3.22"] },
  ]
}

function "metadata" {
  params = [title]
  result = {
    "org.opencontainers.image.source" = "https://github.com/felipecrs/docker-systemd"
    "org.opencontainers.image.title"  = title
  }
}

group "default" {
  targets = ["bin", "image"]
}

target "_common" {
  args = {
    SYSTEMD_REVISION = SYSTEMD_REVISION
  }
  platforms = PLATFORMS
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
  description = "systemd on ${variant.base}"
  inherits    = ["_common"]
  target      = "image"
  contexts = {
    base = "docker-image://${variant.base}"
  }
  tags        = [for tag in variant.tags : "${IMAGE}:${tag}"]
  labels      = metadata("systemd on ${variant.base}")
  annotations = [for k, v in metadata("systemd on ${variant.base}") : "index,manifest:${k}=${v}"]
}

target "check" {
  description = "Lint the Dockerfile"
  call        = "check"
}
