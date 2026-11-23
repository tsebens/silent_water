import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from asset_pipeline import cli, doctor, providers
from asset_pipeline.adapters._net import ImageProviderError
from asset_pipeline.adapters.fal_image import FalImage
from asset_pipeline.adapters.google_image import GoogleImage
from asset_pipeline.adapters.openai_image import OpenAIImage

FIX = Path(__file__).parent / "fixtures"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


class Stub(BaseHTTPRequestHandler):
    """Replays a recorded fixture for every request and logs what it was sent."""
    seen: list = []
    status = 200
    fixture = ""

    def _reply(self):
        n = int(self.headers.get("Content-Length") or 0)
        Stub.seen.append({"method": self.command, "path": self.path, "body": self.rfile.read(n),
                          "headers": {k.lower(): v for k, v in self.headers.items()}})
        if Stub.status == 200:
            data = (FIX / Stub.fixture).read_bytes()
        else:
            data = json.dumps({"error": {"message": f"boom {Stub.status}"}}).encode()
        self.send_response(Stub.status)
        self.send_header("content-type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    do_POST = do_GET = _reply

    def log_message(self, *a):
        pass


@pytest.fixture
def server():
    Stub.seen, Stub.status, Stub.fixture = [], 200, ""
    srv = HTTPServer(("127.0.0.1", 0), Stub)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_port}"
    srv.shutdown()


@pytest.fixture
def refs(tmp_path):
    a, b = tmp_path / "anchor.png", tmp_path / "src.jpg"
    a.write_bytes(PNG_MAGIC + b"anchor")
    b.write_bytes(b"\xff\xd8jpeg")
    return a, b


# ---- OpenAI ----------------------------------------------------------------

def test_openai_generate_without_refs_uses_generations(server, tmp_path, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-o")
    Stub.fixture = "openai_images_response.json"
    out = OpenAIImage(base_url=server).generate("an angler", [], tmp_path / "o" / "x.png")
    assert out.read_bytes().startswith(PNG_MAGIC)
    r = Stub.seen[0]
    assert r["path"] == "/v1/images/generations" and r["headers"]["authorization"] == "Bearer sk-o"
    assert json.loads(r["body"]) == {"model": "gpt-image-2.5-sunburst", "prompt": "an angler", "size": "1024x1024", "n": 1}


def test_openai_references_upload_as_multipart_edit(server, tmp_path, monkeypatch, refs):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-o")
    Stub.fixture = "openai_images_response.json"
    anchor, src = refs
    OpenAIImage(model="gpt-image-x", base_url=server).edit("rotate", src, [anchor], tmp_path / "e.png")
    r = Stub.seen[0]
    assert r["path"] == "/v1/images/edits" and r["headers"]["content-type"].startswith("multipart/form-data; boundary=")
    body = r["body"]
    assert body.count(b'name="image[]"') == 2
    assert body.index(b'filename="src.jpg"') < body.index(b'filename="anchor.png"')  # source first
    assert b"image/jpeg" in body and b"image/png" in body and PNG_MAGIC + b"anchor" in body
    assert b'name="prompt"\r\n\r\nrotate' in body and b"gpt-image-x" in body


def test_openai_live_check(server, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-o")
    Stub.fixture = "openai_images_response.json"
    assert "reachable" in OpenAIImage(base_url=server).live_check()
    assert Stub.seen[0]["method"] == "GET" and Stub.seen[0]["path"] == "/v1/models/gpt-image-2.5-sunburst"


# ---- Google ----------------------------------------------------------------

def test_google_request_shape_and_reply(server, tmp_path, monkeypatch, refs):
    monkeypatch.setenv("GEMINI_API_KEY", "g-key")
    Stub.fixture = "google_generate_response.json"
    anchor, _ = refs
    out = GoogleImage(model="gem-test", base_url=server).generate("an angler", [anchor], tmp_path / "g.png")
    assert out.read_bytes().startswith(PNG_MAGIC)
    r = Stub.seen[0]
    assert r["path"] == "/v1beta/models/gem-test:generateContent" and r["headers"]["x-goog-api-key"] == "g-key"
    body = json.loads(r["body"])
    parts = body["contents"][0]["parts"]
    assert parts[0]["inline_data"]["mime_type"] == "image/png" and parts[-1] == {"text": "an angler"}
    assert body["generationConfig"]["responseModalities"] == ["IMAGE"]


def test_google_edit_puts_source_first(server, tmp_path, monkeypatch, refs):
    monkeypatch.setenv("GEMINI_API_KEY", "g-key")
    Stub.fixture = "google_generate_response.json"
    anchor, src = refs
    GoogleImage(base_url=server).edit("back view", src, [anchor], tmp_path / "g.png")
    parts = json.loads(Stub.seen[0]["body"])["contents"][0]["parts"]
    assert [p.get("inline_data", {}).get("mime_type") for p in parts[:2]] == ["image/jpeg", "image/png"]


def test_google_reply_without_image_is_an_error(server, tmp_path, monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "g-key")
    Stub.fixture = "anthropic_messages_response.json"  # valid JSON, no candidates
    with pytest.raises(ImageProviderError, match="no image"):
        GoogleImage(base_url=server).generate("x", [], tmp_path / "g.png")


# ---- fal -------------------------------------------------------------------

def test_fal_request_shape_and_reference_upload(server, tmp_path, monkeypatch, refs):
    monkeypatch.setenv("FAL_KEY", "fal-k")
    Stub.fixture = "fal_response.json"
    anchor, _ = refs
    out = FalImage(model="fal-ai/flux/dev", base_url=server).generate("an angler", [anchor], tmp_path / "f.png")
    assert out.read_bytes().startswith(PNG_MAGIC)
    r = Stub.seen[0]
    assert r["path"] == "/fal-ai/flux/dev" and r["headers"]["authorization"] == "Key fal-k"
    body = json.loads(r["body"])
    assert body["prompt"] == "an angler" and body["image_urls"][0].startswith("data:image/png;base64,")


def test_fal_edit_uses_edit_model_and_no_refs_omits_images(server, tmp_path, monkeypatch, refs):
    monkeypatch.setenv("FAL_KEY", "fal-k")
    Stub.fixture = "fal_response.json"
    _, src = refs
    f = FalImage(model="m/gen", edit_model="m/edit", base_url=server)
    f.edit("p", src, [], tmp_path / "e.png")
    f.generate("p", [], tmp_path / "g.png")
    assert Stub.seen[0]["path"] == "/m/edit" and "image_urls" in json.loads(Stub.seen[0]["body"])
    assert Stub.seen[1]["path"] == "/m/gen" and "image_urls" not in json.loads(Stub.seen[1]["body"])


def test_fal_downloads_a_url_result(server, tmp_path, monkeypatch):
    monkeypatch.setenv("FAL_KEY", "fal-k")
    Stub.fixture = "fal_response.json"
    reply = json.loads((FIX / "fal_response.json").read_text())
    reply["images"][0]["url"] = server + "/files/img.png"
    (tmp_path / "r.json").write_text(json.dumps(reply))
    # first call returns the URL reply, the follow-up GET fetches the file (any fixture bytes)
    calls = []

    def fake_request(provider, url, headers, body=None, timeout=0, ok_status=()):
        calls.append(url)
        return json.dumps(reply).encode() if body is not None else PNG_MAGIC + b"file"

    monkeypatch.setattr("asset_pipeline.adapters._net.request", fake_request)
    out = FalImage(base_url=server).generate("x", [], tmp_path / "u.png")
    assert out.read_bytes() == PNG_MAGIC + b"file" and calls[1].endswith("/files/img.png")


def test_fal_live_check_accepts_422_after_auth(server, monkeypatch):
    monkeypatch.setenv("FAL_KEY", "fal-k")
    Stub.status = 422
    assert "accepts the key" in FalImage(base_url=server).live_check()
    Stub.status = 401
    with pytest.raises(ImageProviderError, match="HTTP 401"):
        FalImage(base_url=server).live_check()


# ---- error mapping (all adapters) -----------------------------------------------------

ADAPTERS = [(OpenAIImage, "OPENAI_API_KEY"), (GoogleImage, "GEMINI_API_KEY"), (FalImage, "FAL_KEY")]


@pytest.mark.parametrize("cls,key", ADAPTERS)
@pytest.mark.parametrize("status,match", [
    (401, "authentication failed.*boom 401"), (403, "authentication failed"), (429, "rate limited"),
    (400, "request rejected.*boom 400"), (500, "server error"),
])
def test_http_errors_are_mapped(cls, key, status, match, server, tmp_path, monkeypatch):
    monkeypatch.setenv(key, "k")
    Stub.status = status
    with pytest.raises(ImageProviderError, match=match):
        cls(base_url=server).generate("x", [], tmp_path / "x.png")
    assert not (tmp_path / "x.png").exists()


@pytest.mark.parametrize("cls,key", ADAPTERS)
def test_missing_key_and_unreachable(cls, key, server, tmp_path, monkeypatch):
    monkeypatch.delenv(key, raising=False)
    with pytest.raises(ImageProviderError, match=key):
        cls(base_url=server).generate("x", [], tmp_path / "x.png")
    assert Stub.seen == []
    monkeypatch.setenv(key, "k")
    with pytest.raises(ImageProviderError, match="unreachable"):
        cls(base_url="http://127.0.0.1:1").generate("x", [], tmp_path / "x.png")


def test_unsupported_reference_type(server, tmp_path, monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "k")
    bad = tmp_path / "a.gif"
    bad.write_bytes(b"GIF")
    with pytest.raises(ImageProviderError, match="unsupported image type"):
        GoogleImage(base_url=server).generate("x", [bad], tmp_path / "x.png")


# ---- registration is config only -------------------------------------------------------

def test_new_provider_by_config_only_and_commands_use_it(server, root, monkeypatch):
    """A provider on an existing adapter needs only a providers.yaml entry; the commands are untouched."""
    monkeypatch.setenv("FAL_KEY", "fal-k")
    Stub.fixture = "fal_response.json"
    cfg = providers.load_config()
    cfg["providers"]["image"]["kontext"] = {"adapter": "fal", "model": "fal-ai/kontext", "base_url": server}
    prov = providers.select("image", cfg, override="kontext")
    assert isinstance(prov, FalImage) and prov.name == "kontext" and prov.model == "fal-ai/kontext"
    monkeypatch.setattr(providers, "load_config", lambda path=None: cfg)
    assert cli.main(["new", "angler", "--class", "creature"]) == 0
    assert cli.main(["concept", "angler", "--n", "1", "--brief", "an angler", "--image-provider", "kontext"]) == 0
    assert Stub.seen[0]["path"] == "/fal-ai/kontext"
    manifest = (root / "assets/models/angler/asset.yaml").read_text()
    assert "provider: kontext" in manifest and "model: fal-ai/kontext" in manifest


def test_real_adapters_are_registered_with_default_config():
    cfg = providers.load_config()
    for name, cls in (("openai", OpenAIImage), ("google", GoogleImage), ("fal", FalImage)):
        assert isinstance(providers.select("image", cfg, override=name), cls)


# ---- doctor ---------------------------------------------------------------------------

def checks(result):
    return {c["name"]: c for c in result["checks"]}


@pytest.fixture
def clean_env(monkeypatch, tmp_path):
    for k in ("OPENAI_API_KEY", "GEMINI_API_KEY", "FAL_KEY", "ANTHROPIC_API_KEY", "TRIPO_API_KEY",
              "MESHY_API_KEY", "RODIN_API_KEY"):
        monkeypatch.delenv(k, raising=False)
    fake = tmp_path / "bin"
    fake.mkdir()
    for n, out in (("blender", "Blender 4.5.3 LTS"), ("godot", "4.7.2.stable.official.deadbeef"), ("claude", "")):
        (fake / n).write_text(f"#!/bin/sh\necho '{out}'\n")
        (fake / n).chmod(0o755)
    monkeypatch.setenv("PATH", str(fake))
    for k in ("ASSET_BLENDER_BIN", "GODOT", "ASSET_CLAUDE_BIN"):
        monkeypatch.delenv(k, raising=False)


def test_doctor_reports_pass_and_fail_with_reasons(clean_env, monkeypatch):
    monkeypatch.setenv("PATH", "/nonexistent")
    r = doctor.run(providers.load_config())
    c = checks(r)
    assert r["ok"] is False
    assert not c["blender"]["ok"] and "ASSET_BLENDER_BIN" in c["blender"]["detail"]
    assert not c["godot"]["ok"] and "GODOT" in c["godot"]["detail"]
    assert c["image:openai key"]["detail"] == "OPENAI_API_KEY is not set"


def _stub(tmp_path, monkeypatch, blender, godot):
    for n, out in (("blender", blender), ("godot", godot)):
        (tmp_path / "bin" / n).write_text(f"#!/bin/sh\necho '{out}'\n")


def test_doctor_checks_tool_versions(clean_env, tmp_path, monkeypatch):
    _stub(tmp_path, monkeypatch, "Blender 4.2.1 LTS", "4.7.2.stable.mono.official.deadbeef")
    r = doctor.run(providers.load_config())
    c = checks(r)
    assert r["ok"] is False
    assert not c["blender"]["ok"] and "Blender 4.2.1" in c["blender"]["detail"] and "Blender 4.5.x" in c["blender"]["detail"]
    assert not c["godot"]["ok"] and "mono" in c["godot"]["detail"] and "4.7.2 standard" in c["godot"]["detail"]
    _stub(tmp_path, monkeypatch, "Blender 4.5.0 LTS", "4.6.0.stable.official.deadbeef")
    c = checks(doctor.run(providers.load_config()))
    assert not c["godot"]["ok"] and "4.6.0" in c["godot"]["detail"] and "4.7.2" in c["godot"]["detail"]
    _stub(tmp_path, monkeypatch, "Blender 4.5.0 LTS", "4.7.2.stable.official.deadbeef")
    r = doctor.run(providers.load_config())
    assert r["ok"] is True


def test_doctor_all_green_and_only_selected_required(clean_env):
    r = doctor.run(providers.load_config())
    c = checks(r)
    assert c["blender"]["ok"] and c["godot"]["ok"] and c["claude CLI"]["ok"]
    assert not c["image:openai key"]["ok"] and not c["image:openai key"]["required"]
    assert r["ok"] is True  # the default selection is all mock; unselected missing keys do not fail it


def test_doctor_selected_provider_needs_its_key(clean_env, monkeypatch):
    cfg = providers.load_config()
    cfg["selection"]["image"] = "openai"
    assert doctor.run(cfg)["ok"] is False
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    assert doctor.run(cfg)["ok"] is True


def test_doctor_live_runs_one_call_per_keyed_provider(clean_env, server, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    monkeypatch.setenv("FAL_KEY", "k")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k")
    Stub.fixture = "openai_images_response.json"
    cfg = providers.load_config()
    # Point every hosted provider at the stub, so a newly configured one can never reach the
    # real API (a proxy on a dev machine can hide that from the network guard; CI has none).
    for kind in ("image", "three_d"):
        for name, entry in cfg["providers"][kind].items():
            if name != "mock" and isinstance(entry, dict):
                entry["base_url"] = server
    monkeypatch.setattr(doctor, "_anthropic_live", lambda: "mock models list")
    assert [s["path"] for s in Stub.seen] == []
    off = doctor.run(cfg, live=False)
    assert Stub.seen == [] and not any(c["name"].endswith("live") for c in off["checks"])
    on = checks(doctor.run(cfg, live=True))
    assert on["image:openai live"]["ok"] and on["image:fal live"]["ok"] and on["prompt_writer:anthropic-api live"]["ok"]
    assert "image:google live" not in on  # no key, no call
    assert sorted(s["path"] for s in Stub.seen) == ["/fal-ai/flux-pro/v1.1", "/fal-ai/trellis-2", "/fal-ai/trellis/multi",
                                                   "/v1/models/gpt-image-2.5-sunburst"]
    Stub.status = 401
    bad = checks(doctor.run(cfg, live=True))
    assert not bad["image:openai live"]["ok"] and "HTTP 401" in bad["image:openai live"]["detail"]


def test_doctor_command_prints_json_and_exits_nonzero_on_failure(root, clean_env, capsys, monkeypatch):
    monkeypatch.setenv("PATH", "/nonexistent")
    assert cli.main(["doctor"]) == 1
    out = json.loads(capsys.readouterr().out)
    assert out["ok"] is False and out["checks"]


# ---- concept --reference reaches each adapter's request ---------------------

@pytest.mark.parametrize("make,fixture,key,env", [
    (lambda url: OpenAIImage(base_url=url), "openai_images_response.json", "OPENAI_API_KEY", "/v1/images/edits"),
    (lambda url: GoogleImage(base_url=url), "google_generate_response.json", "GEMINI_API_KEY", ":generateContent"),
    (lambda url: FalImage(model="m/gen", edit_model="m/edit", base_url=url), "fal_response.json", "FAL_KEY", "/m/edit"),
])
def test_concept_paint_over_reference_reaches_the_request(server, tmp_path, monkeypatch, capsys, make, fixture, key, env):
    import base64

    from PIL import Image
    root = tmp_path / "repo"
    root.mkdir()
    (root / "project.godot").write_text("")
    monkeypatch.setenv("ASSET_PIPELINE_ROOT", str(root))
    monkeypatch.setenv(key, "k")
    Stub.fixture = fixture
    ref = tmp_path / "blockout.jpg"
    Image.new("RGB", (16, 16), (10, 200, 10)).save(ref, format="JPEG")
    prov = make(server)
    prov.name = "real"
    real_select = providers.select
    monkeypatch.setattr(providers, "select", lambda kind, cfg, override=None:
                        prov if kind == "image" else real_select(kind, cfg, override))
    assert cli.main(["new", "cabin", "--class", "prop"]) == 0
    capsys.readouterr()
    assert cli.main(["concept", "cabin", "--brief", "a cabin", "--n", "1", "--reference", str(ref)]) == 0
    stored = next((root / ".asset_work" / "cabin" / "references").iterdir()).read_bytes()
    r = Stub.seen[0]
    assert env in r["path"]
    assert stored in r["body"] or base64.b64encode(stored) in r["body"]  # the reference itself is in the request
