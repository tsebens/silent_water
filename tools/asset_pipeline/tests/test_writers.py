import json
import os
import stat
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from asset_pipeline import providers
from asset_pipeline.writers import AnthropicApiWriter, ClaudeCliWriter, PromptWriterError, parse_prompts

FIX = Path(__file__).parent / "fixtures"


def stub_claude(tmp_path, stdout, code=0, stderr=""):
    """A stand-in `claude` that logs its argv and prints canned output."""
    log = tmp_path / "argv.json"
    script = tmp_path / "claude"
    script.write_text(
        "#!/usr/bin/env python3\nimport json, sys\n"
        f"json.dump(sys.argv[1:], open({str(log)!r}, 'w'))\n"
        f"sys.stdout.write({stdout!r})\nsys.stderr.write({stderr!r})\nsys.exit({code})\n")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return str(script), log


def reply(result, is_error=False):
    return json.dumps({"type": "result", "subtype": "success", "is_error": is_error, "result": result})


def test_cli_command_line_and_parsing(tmp_path):
    cmd, log = stub_claude(tmp_path, reply('["p one", "p two"]'))
    img = tmp_path / "imgs" / "a.png"
    img.parent.mkdir()
    img.write_bytes(b"x")
    w = ClaudeCliWriter(model="claude-test", command=cmd)
    assert w.write_prompts("an angler", "STYLE", "longer lure", [img], 2) == ["p one", "p two"]
    argv = json.loads(log.read_text())
    assert argv[0] == "-p" and "an angler" in argv[1] and "longer lure" in argv[1] and str(img.resolve()) in argv[1]
    assert argv[argv.index("--output-format") + 1] == "json"
    assert argv[argv.index("--model") + 1] == "claude-test"
    assert argv[argv.index("--add-dir") + 1] == str(img.parent.resolve())
    assert argv[argv.index("--allowedTools") + 1] == "Read"


def test_cli_brief_and_fenced_json(tmp_path):
    cmd, _ = stub_claude(tmp_path, reply("# Brief\n\nSize: 4 m"))
    assert ClaudeCliWriter(command=cmd).write_brief("ctx", []) == "# Brief\n\nSize: 4 m\n"
    cmd, _ = stub_claude(tmp_path, reply('Sure:\n```json\n["a", "b"]\n```'))
    assert ClaudeCliWriter(command=cmd).write_prompts("b", "s", "", [], 2) == ["a", "b"]


@pytest.mark.parametrize("stdout,code,stderr,match", [
    ("", 1, "not logged in", "exited 1: not logged in"),
    ("not json", 0, "", "did not print JSON"),
    (reply("rate limited", is_error=True), 0, "", "reported an error"),
    (json.dumps({"type": "result", "is_error": False}), 0, "", "no result text"),
    (reply("no array here"), 0, "", "no JSON array"),
    (reply('["only one"]'), 0, "", "wanted 2"),
])
def test_cli_error_mapping(tmp_path, stdout, code, stderr, match):
    cmd, _ = stub_claude(tmp_path, stdout, code, stderr)
    with pytest.raises(PromptWriterError, match=match):
        ClaudeCliWriter(command=cmd).write_prompts("b", "s", "", [], 2)


def test_cli_failure_shows_result_after_long_usage_block(tmp_path):
    # Seen on Windows: exit 1, JSON whose usage block fills the first 500 characters and whose
    # actual message is in `result` at the end. The error must show that message.
    out = {"duration_api_ms": 0, "total_cost_usd": 0,
           "usage": {"input_tokens": 0, "output_tokens": 0, "padding": "x" * 600},
           "is_error": True, "subtype": "error_during_execution",
           "result": "Not logged in · Please run /login"}
    cmd, _ = stub_claude(tmp_path, json.dumps(out), code=1)
    with pytest.raises(PromptWriterError, match="exited 1: Not logged in · Please run /login"):
        ClaudeCliWriter(command=cmd).write_prompts("b", "s", "", [], 2)


def test_cli_failure_falls_back_to_output_tail(tmp_path):
    cmd, _ = stub_claude(tmp_path, "x" * 900 + "THE END", code=2)
    with pytest.raises(PromptWriterError, match="THE END"):
        ClaudeCliWriter(command=cmd).write_prompts("b", "s", "", [], 2)


def test_cli_missing_executable(tmp_path):
    with pytest.raises(PromptWriterError, match="not found"):
        ClaudeCliWriter(command=str(tmp_path / "nope")).write_prompts("b", "s", "", [], 1)


class Recorder(BaseHTTPRequestHandler):
    seen: list = []
    status = 200

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        Recorder.seen.append({"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(body)})
        data = (FIX / "anthropic_messages_response.json").read_bytes() if Recorder.status == 200 \
            else b'{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'
        self.send_response(Recorder.status)
        self.send_header("content-type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


@pytest.fixture
def server():
    Recorder.seen, Recorder.status = [], 200
    srv = HTTPServer(("127.0.0.1", 0), Recorder)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_port}"
    srv.shutdown()


def test_api_writer_request_shape_and_fixture_reply(server, tmp_path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-test")
    monkeypatch.setenv("CLAUDE_CODE_OAUTH_TOKEN", "oauth-secret")
    img = tmp_path / "a.png"
    img.write_bytes(b"\x89PNG")
    w = AnthropicApiWriter(model="claude-test", base_url=server)
    assert w.write_prompts("an angler", "STYLE", "", [img], 2) == [
        "a hulking anglerfish with a sodium-red lure", "a flattened angler hugging the seabed"]
    req = Recorder.seen[0]
    assert req["path"] == "/v1/messages"
    assert req["headers"]["x-api-key"] == "sk-test" and "anthropic-version" in req["headers"]
    assert "oauth-secret" not in json.dumps(req)  # the OAuth token is never sent
    assert "authorization" not in {k.lower() for k in req["headers"]}
    body = req["body"]
    assert body["model"] == "claude-test" and body["max_tokens"] > 0
    parts = body["messages"][0]["content"]
    assert parts[0]["type"] == "image" and parts[0]["source"]["media_type"] == "image/png"
    assert "an angler" in parts[-1]["text"]


def test_api_writer_errors(server, monkeypatch, tmp_path):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("CLAUDE_CODE_OAUTH_TOKEN", "oauth-secret")
    w = AnthropicApiWriter(base_url=server)
    with pytest.raises(PromptWriterError, match="ANTHROPIC_API_KEY"):
        w.write_brief("c", [])
    assert Recorder.seen == []  # OAuth token alone never produces a request
    monkeypatch.setenv("ANTHROPIC_API_KEY", "bad")
    Recorder.status = 401
    with pytest.raises(PromptWriterError, match="HTTP 401.*invalid x-api-key"):
        w.write_brief("c", [])


def test_registered_and_selectable():
    cfg = providers.load_config()
    assert isinstance(providers.select("prompt_writer", cfg, "claude-cli"), ClaudeCliWriter)
    assert providers.select("prompt_writer", cfg, "anthropic-api").model == "claude-sonnet-5-5"


def test_parse_prompts_rejects_non_strings():
    with pytest.raises(PromptWriterError):
        parse_prompts("[1, 2]", 2)
