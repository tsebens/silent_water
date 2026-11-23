"""Blender runner selection, the Docker command and its manifest record. A stub `docker` on PATH stands in for the
daemon, so nothing here needs Docker or Blender. The `needs_docker` test runs the real fixture cleanup."""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from asset_pipeline import cleanup, cli, doctor, providers
from asset_pipeline.manifest import Manifest
from test_cleanup import assert_cleanup_meets_the_profile, asset, run  # noqa: F401  (the `asset` fixture)

PIPE = Path(__file__).resolve().parents[1]
RESULT = {"blender_version": "4.5.9", "triangles": 1, "non_manifold": 0}


def make_stub(path: Path, name: str, body: str) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    f = path / name
    f.write_text("#!/bin/bash\n" + body)
    f.chmod(f.stat().st_mode | stat.S_IEXEC)
    return f


STUB_DOCKER = r'''
echo "$@" >> "$STUB_LOG"
case "$1" in
  info) exit ${STUB_INFO_RC:-0};;
  image) [ "${STUB_IMAGE:-1}" = 1 ] || exit 1
         echo '["silent-water/blender-cleanup@sha256:abc123"]|sha256:def456'; exit 0;;
  run) if [ "$4" = "--version" ] || [ "${@: -1}" = "--version" ]; then echo "Blender ${STUB_BLENDER:-4.5.9 LTS}"; exit 0; fi
       echo "Pulling from silent-water/blender-cleanup" >&2
       echo "ASSET_CLEANUP_RESULT $STUB_RESULT"; exit 0;;
esac
'''


@pytest.fixture
def env(tmp_path, monkeypatch):
    """PATH holds only a stub docker (and no blender); returns the bin dir and the log of docker invocations."""
    bindir = tmp_path / "bin"
    make_stub(bindir, "docker", STUB_DOCKER)
    log = tmp_path / "docker.log"
    monkeypatch.setenv("PATH", str(bindir))
    monkeypatch.setenv("STUB_LOG", str(log))
    monkeypatch.setenv("STUB_RESULT", json.dumps(RESULT))
    for k in ("ASSET_BLENDER_BIN", "ASSET_BLENDER_RUNNER", "ASSET_BLENDER_IMAGE"):
        monkeypatch.delenv(k, raising=False)
    return bindir, log


def add_blender(bindir):
    make_stub(bindir, "blender", 'echo "Blender 4.5.9 LTS"\n')


# --- resolution -----------------------------------------------------------------------------------------------

def test_auto_prefers_native_then_docker_then_errors(env, monkeypatch):
    bindir, _ = env
    assert cleanup.resolve_runner().kind == "docker"
    add_blender(bindir)
    assert cleanup.resolve_runner().kind == "native"
    monkeypatch.setenv("ASSET_BLENDER_BIN", "nope")  # a missing binary does not win
    assert cleanup.resolve_runner().kind == "docker"
    monkeypatch.setenv("STUB_INFO_RC", "1")  # daemon down
    with pytest.raises(cleanup.BlenderUnavailable) as e:
        cleanup.resolve_runner()
    assert "ASSET_BLENDER_BIN" in str(e.value) and "asset blender-image build" in str(e.value)
    assert "Install Docker" not in str(e.value) and "Blender 4.5 LTS" in str(e.value)


def test_forced_runners(env, monkeypatch):
    bindir, _ = env
    add_blender(bindir)
    monkeypatch.setenv("ASSET_BLENDER_RUNNER", "docker")
    assert cleanup.resolve_runner().kind == "docker"
    monkeypatch.setenv("ASSET_BLENDER_RUNNER", "native")
    assert cleanup.resolve_runner().kind == "native"
    (bindir / "blender").unlink()
    with pytest.raises(cleanup.BlenderUnavailable, match="Blender not found"):
        cleanup.resolve_runner()
    monkeypatch.setenv("ASSET_BLENDER_RUNNER", "docker")
    monkeypatch.setenv("STUB_INFO_RC", "1")
    with pytest.raises(cleanup.BlenderUnavailable, match="daemon"):
        cleanup.resolve_runner()
    monkeypatch.setenv("ASSET_BLENDER_RUNNER", "weird")
    with pytest.raises(ValueError, match="ASSET_BLENDER_RUNNER"):
        cleanup.resolve_runner()


def test_image_default_and_override(env, monkeypatch):
    assert cleanup.image_name() == f"silent-water/blender-cleanup:{cleanup.blender_version()}"
    monkeypatch.setenv("ASSET_BLENDER_IMAGE", "me/blender:x")
    assert cleanup.resolve_runner().image == "me/blender:x"


# --- the Docker command, params and manifest ---------------------------------------------------------------------

def test_docker_command_and_user_by_platform(root, env, monkeypatch):
    runner = cleanup.Runner("docker", "docker", "img:1")
    cmd = cleanup.docker_command(runner, root, ".asset_work/blob/cleanup/cleanup_params.json")
    assert cmd[:3] == ["docker", "run", "--rm"]
    assert cmd[cmd.index("-v") + 1] == f"{root}:/work" and cmd[cmd.index("-w") + 1] == "/work"
    i = cmd.index("img:1")
    assert cmd[i + 1:] == ["-b", "--factory-startup", "-P", "/work/tools/asset_pipeline/asset_pipeline/blender/cleanup_bpy.py",
                           "--", "/work/.asset_work/blob/cleanup/cleanup_params.json"]
    assert cleanup.SCRIPT.as_posix().endswith(cleanup.SCRIPT_REL)
    if sys.platform != "win32":
        assert cmd[cmd.index("--user") + 1] == f"{os.getuid()}:{os.getgid()}"
    monkeypatch.setattr(cleanup.sys, "platform", "win32")
    assert "--user" not in cleanup.docker_command(runner, root, "p.json")
    # nothing from the environment is passed on the command line
    assert not {"-e", "--env", "--env-file"} & set(cmd)


def test_cleanup_through_stub_docker_records_runner_and_image(asset, env, capsys):
    _, log = env
    assert run("cleanup", "blob", "--source", "r1_mock") == 0
    cap = capsys.readouterr()
    assert json.loads(cap.out)["ok"] is True
    assert "Pulling from" in cap.err  # container stderr becomes progress
    lines = log.read_text().splitlines()
    runline = next(l for l in lines if l.startswith("run "))
    assert "-v " + f"{asset}:/work" in runline and "-w /work silent-water/blender-cleanup:" in runline
    assert not re.search(r"(^| )(-e|--env|--env-file)( |$)", runline)
    params = json.loads((asset / ".asset_work" / "blob" / "cleanup" / "cleanup_params.json").read_text())
    assert params["root"] == "/work"
    assert params["source"] == ".asset_work/blob/to3d/r1_mock.glb" and params["output"] == ".asset_work/blob/cleanup/c1.glb"
    rec = Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml").cleanups[0]
    assert rec.runner == "docker" and rec.image.endswith("@sha256:abc123") and rec.blender == "4.5.9"


def test_native_runner_writes_same_relative_params(asset, env, monkeypatch, tmp_path, capsys):
    bindir, _ = env
    make_stub(bindir, "blender", f'echo "ASSET_CLEANUP_RESULT $STUB_RESULT"\n')
    assert run("cleanup", "blob", "--source", "r1_mock") == 0
    params = json.loads((asset / ".asset_work" / "blob" / "cleanup" / "cleanup_params.json").read_text())
    assert params["root"] == asset.as_posix() and params["source"] == ".asset_work/blob/to3d/r1_mock.glb"
    rec = Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml").cleanups[0]
    assert rec.runner == "native" and rec.image == ""


def test_source_outside_repo_is_an_error(asset, env, capsys):
    mpath = asset / "assets" / "models" / "blob" / "asset.yaml"
    m = Manifest.load(mpath)
    m.entry("r1_mock").path = "../elsewhere.glb"
    m.save(mpath)
    assert run("cleanup", "blob", "--source", "r1_mock") == 1
    assert "outside the repo root" in json.loads(capsys.readouterr().out)["error"]
    assert not any(l.startswith("run ") for l in (env[1].read_text().splitlines() if env[1].exists() else []))


def test_docker_failure_hints_at_building_the_image(asset, env, capsys):
    bindir, _ = env
    make_stub(bindir, "docker", 'case "$1" in info) exit 0;; image) exit 1;; esac\n'
              'echo "Unable to find image \'x\' locally" >&2; exit 125\n')
    assert run("cleanup", "blob", "--source", "r1_mock") == 1
    assert "asset blender-image build" in json.loads(capsys.readouterr().out)["error"]


# --- doctor ---------------------------------------------------------------------------------------------------

def blender_check():
    return next(c for c in doctor.run(providers.load_config())["checks"] if c["name"] == "blender")


def test_doctor_native(env):
    add_blender(env[0])
    c = blender_check()
    assert c["ok"] and "Blender 4.5.9" in c["detail"] and "docker" not in c["detail"]


def test_doctor_docker_and_missing_image(env, monkeypatch):
    c = blender_check()
    assert c["ok"] and c["detail"] == f"docker: {cleanup.image_name()}, Blender 4.5.9 LTS"
    monkeypatch.setenv("STUB_BLENDER", "4.2.1 LTS")
    assert not blender_check()["ok"]
    monkeypatch.setenv("STUB_IMAGE", "0")
    c = blender_check()
    assert not c["ok"] and "asset blender-image build" in c["detail"]


def test_doctor_neither(env, monkeypatch):
    monkeypatch.setenv("STUB_INFO_RC", "1")
    c = blender_check()
    assert not c["ok"] and "ASSET_BLENDER_BIN" in c["detail"] and "asset blender-image build" in c["detail"]


# --- image build ----------------------------------------------------------------------------------------------

def test_dockerfile_default_version_matches_versions_yaml():
    text = (PIPE / "docker" / "blender.Dockerfile").read_text()
    default = re.search(r"^ARG BLENDER_VERSION=(\S+)", text, re.MULTILINE).group(1)
    want = yaml.safe_load((PIPE / "versions.yaml").read_text())["blender"]["version"]
    assert default == want and want.startswith(yaml.safe_load((PIPE / "versions.yaml").read_text())["blender"]["major_minor"])
    assert 'ENTRYPOINT ["blender"]' in text and ".sha256" in text


def test_blender_image_build_passes_version(env, capsys):
    _, log = env
    assert run("blender-image", "build") == 0
    out = json.loads(capsys.readouterr().out)
    assert out["blender"] == cleanup.blender_version()
    line = next(l for l in log.read_text().splitlines() if l.startswith("build "))
    assert f"--build-arg BLENDER_VERSION={cleanup.blender_version()}" in line and f"-t {out['image']}" in line


# --- integration ----------------------------------------------------------------------------------------------

def _daemon() -> bool:
    d = shutil.which("docker")
    return bool(d) and subprocess.run([d, "info"], capture_output=True).returncode == 0 and \
        subprocess.run([d, "image", "inspect", cleanup.image_name()], capture_output=True).returncode == 0


needs_docker = pytest.mark.skipif(not _daemon(), reason="no Docker daemon with the Blender image (asset blender-image build)")


@needs_docker
def test_docker_cleanup_meets_the_native_assertions(asset, monkeypatch, capsys):
    monkeypatch.setenv("ASSET_BLENDER_RUNNER", "docker")
    script = asset / cleanup.SCRIPT_REL  # the container sees only the (temporary) repo root
    script.parent.mkdir(parents=True)
    shutil.copy(cleanup.SCRIPT, script)
    assert_cleanup_meets_the_profile(asset, capsys)
    assert Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml").cleanups[0].runner == "docker"
