import json
import subprocess
import time

import pytest

OPTIONS = [
    "--tty",
    "--tmpfs=/run:exec",
    "--tmpfs=/run/lock:exec",
    "--tmpfs=/tmp:exec",
    "--security-opt=writable-cgroups=true",
]


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True, timeout=60).strip()


def images():
    definition = subprocess.check_output(
        ["docker", "buildx", "bake", "--print", "image"], stderr=subprocess.DEVNULL
    )
    return [target["tags"][0] for target in json.loads(definition)["target"].values()]


@pytest.fixture(params=images())
def run(request):
    containers = []

    def run(*options, command=()):
        container = docker("create", *OPTIONS, *options, request.param, *command)
        containers.append(container)
        docker("start", container)
        return container

    yield run

    for container in containers:
        # only shown by pytest if the test fails
        print(docker("logs", container))
        docker("rm", "--force", container)


def exit_code(container):
    return int(docker("wait", container))


def test_stops_cleanly(run):
    container = run()

    deadline = time.monotonic() + 30
    while "Startup finished" not in docker("logs", container):
        assert time.monotonic() < deadline, "did not finish booting"
        time.sleep(0.1)

    docker("stop", container)
    assert exit_code(container) == 0


@pytest.mark.parametrize("code", [0, 3])
def test_propagates_exit_code_of_service(run, tmp_path, code):
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
        f"--volume={unit}:/etc/systemd/system/test.service:ro",
        command=["--unit=test.service"],
    )
    assert exit_code(container) == code
