# AGENTS.md

Container images with systemd as PID 1, built from a single static binary. Read the [README](README.md) first, as it explains why everything is the way it is.

## Commands

Tools and tasks are managed by [mise](https://mise.jdx.dev):

```sh
mise run build             # build everything
mise run build noble       # build a single target
mise run test              # test all variants
mise run test -k noble     # test a single variant
mise run lint              # check everything
mise run fix               # fix everything that can be fixed
hk install --mise          # optional, do it on every commit
```

Building and testing everything takes minutes. For a small change, only build and test what it affects, and let ci do the rest.

## Layout

- `Dockerfile`: the systemd binary (`bin`), and the image for each distro (`image`)
- `dind/`: an image built on top of these, with its own `Dockerfile` and `README.md`
- `passt/`: the passt binary, used by `dind/`
- `docker-bake.hcl`: all targets and tags
- `policy.rego`: the sources that builds are allowed to use
- `test_images.py`: tests, which run the images that were built before

To add a distro, add a stage for it to the `Dockerfile`, and an entry to `VARIANTS`.

To add another kind of image, such as dind, create a directory with a `Dockerfile` that starts from the `systemd` context, a target for it in `docker-bake.hcl` that is also part of the `images` group, and tests.

## Guidelines

- Keep it simple. Prefer removing over adding, and do not support old versions of anything when a newer one makes it simpler.
- Never use `--privileged`. Options needed to run an image are passed by the user and documented, not worked around in an entrypoint.
- Everything that is not obvious needs a reason, in a comment or README, with links to upstream issues and PRs. Test it before claiming it.
- Workarounds get a `TODO` with what they are waiting for.
- Tags follow the Docker Official Images.
- In Dockerfiles, write scripts as `<<-'EOF'` indented with tabs, pin downloads, and list what to copy instead of whole directories.
- Dependencies have to be updatable by Renovate, preferably by its built-in managers.

## Pull requests

- Titles follow [Conventional Commits](https://www.conventionalcommits.org), as they become the commit message.
- Descriptions are short, and say what changed and why.
- Nothing is published from pull requests. Images are published from `master`, after all tests pass.
- Jobs that have to pass before merging go in the `needs` of `required-checks-passed`.
