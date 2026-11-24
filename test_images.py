import json
import lzma
import subprocess
import tarfile
import time

import pytest

OPTIONS = ["--tmpfs=/run", "--security-opt=writable-cgroups=true"]

DIND_OPTIONS = [
    *OPTIONS,
    "--cap-add=NET_ADMIN",
    "--cap-add=SYS_ADMIN",
    "--security-opt=apparmor=unconfined",
    "--security-opt=seccomp=unconfined",
    "--security-opt=systempaths=unconfined",
    "--stop-timeout=30",
]


def docker(*args, **kwargs):
    kwargs = {"text": True, "timeout": 120} | kwargs
    return subprocess.check_output(["docker", *args], **kwargs).strip()


def images(group):
    definition = docker("buildx", "bake", "--print", group, stderr=subprocess.DEVNULL)
    definition = json.loads(definition)
    # the targets they depend on are also in the definition
    targets = definition["group"][group]["targets"]
    return [definition["target"][target]["tags"][0] for target in targets]


@pytest.fixture
def run():
    containers = []

    def run(image, *options, command=()):
        container = docker("create", "--tty", *options, image, *command)
        containers.append(container)
        docker("start", container)
        return container

    yield run

    for container in containers:
        # only shown by pytest if the test fails
        print(docker("logs", container))
        docker("rm", "--force", "--volumes", container)


def wait_for_boot(container):
    deadline = time.monotonic() + 60
    while "Startup finished" not in docker("logs", container):
        assert time.monotonic() < deadline, "did not finish booting"
        time.sleep(0.1)


def exit_code(container):
    return int(docker("wait", container))


@pytest.mark.parametrize("image", images("image"))
def test_stops_cleanly(run, image):
    container = run(image, *OPTIONS)
    wait_for_boot(container)

    docker("stop", container)
    assert exit_code(container) == 0


@pytest.mark.parametrize("image", images("image"))
@pytest.mark.parametrize("code", [0, 3])
def test_propagates_exit_code_of_service(run, image, tmp_path, code):
    unit = tmp_path / "test.service"
    unit.write_text(f"""
[Unit]
SuccessAction=exit
FailureAction=exit

[Service]
Type=oneshot
ExecStart=/bin/sh -c "exit {code}"
""")

    container = run(
        image,
        *OPTIONS,
        f"--volume={unit}:/etc/systemd/system/test.service:ro",
        command=["--unit=test.service"],
    )
    assert exit_code(container) == code


@pytest.mark.parametrize("image", images("dind"))
def test_dind(run, image):
    container = run(image, *DIND_OPTIONS)
    wait_for_boot(container)

    def nested(*args, **kwargs):
        return docker("exec", "--interactive", container, "docker", *args, **kwargs)

    # builds, with network
    dockerfile = "FROM alpine\nRUN wget -q -O /dev/null https://www.docker.com"
    nested("build", "--tag=test", "-", input=dockerfile)

    # runs, with network and limits
    nested(
        "run", "--rm", "test", "wget", "-q", "-O", "/dev/null", "https://www.docker.com"
    )
    limit = nested(
        "run", "--rm", "--memory=64m", "test", "cat", "/sys/fs/cgroup/memory.max"
    )
    assert int(limit) == 64 * 1024 * 1024

    # needs git
    dockerfile = "FROM scratch\nADD https://github.com/docker-library/hello-world.git /"
    nested("build", "-", input=dockerfile)

    # needs xz
    archive = lzma.compress(tarfile.TarInfo("test").tobuf() + bytes(1024))
    nested("import", "-", input=archive, text=None)

    # needs ps
    nested("run", "--detach", "--name=test", "test", "sleep", "infinity")
    assert "sleep infinity" in nested("top", "test")

    nested("compose", "version")

    docker("stop", container)
    assert exit_code(container) == 0
