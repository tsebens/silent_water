"""Real PromptWriter adapters: the Claude Code CLI and the Anthropic Messages API.

The CLI writer authenticates through Claude Code itself (logged-in subscription or
CLAUDE_CODE_OAUTH_TOKEN, both read by `claude`, never by this module). The API writer
uses ANTHROPIC_API_KEY only. The OAuth token is never put into a Messages API call.
"""
from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

from .providers import REGISTRY, PromptWriter

IMAGE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}


class PromptWriterError(RuntimeError):
    """The writer could not produce text (missing tool, auth, HTTP or malformed output)."""


MODE_TEXT = {
    "paint-over": ("The FIRST attached image is a reference to paint over. KEEP its composition, camera, "
                   "proportions and major shapes exactly; change only materials, surface detail, colour and "
                   "lighting to match the style bible. Every prompt must say so.\n"),
    "inspire": ("The FIRST attached image is a loose visual starting point. Take mood, motifs and shapes from it, "
                "but the composition, camera and proportions may change freely.\n"),
}


def prompts_request(brief: str, style: str, notes: str, n: int, has_images: bool, mode: str | None = None) -> str:
    refs = ("The attached images are style anchors (and, when refining, the parent variant). "
            "Match their look and, when refining, keep what the notes do not change.\n") if has_images else ""
    return (
        f"You write image-generation prompts for a game concept artist.\n\n"
        f"STYLE BIBLE (the generator is given this separately; do not repeat it):\n{style}\n\n"
        f"ASSET BRIEF:\n{brief}\n\n"
        + (f"REFINE NOTES (what to change):\n{notes}\n\n" if notes else "")
        + refs
        + (MODE_TEXT[mode] + "\n" if mode else "")
        + f"Write {n} distinct prompts for one hero concept image of this asset, differing in "
        f"silhouette or composition. Reply with ONLY a JSON array of {n} strings."
    )


def brief_request(context: str, has_images: bool) -> str:
    return (
        "Draft brief.md for a 3D asset from the context below"
        + (" and the attached concept and turnaround images" if has_images else "")
        + ". Use these sections: Size (metres), Triangle budget, Snap grid, Palette, Emissive (neon) "
        "placement, Notes. Reply with ONLY the markdown.\n\nCONTEXT:\n" + context
    )


def parse_prompts(text: str, n: int) -> list[str]:
    """Pull a JSON array of `n` strings out of a model reply (tolerates code fences and prose)."""
    s = text.strip()
    s = re.sub(r"^```(?:json)?\s*|\s*```$", "", s)
    start, end = s.find("["), s.rfind("]")
    if start < 0 or end < start:
        raise PromptWriterError("writer reply contains no JSON array of prompts")
    try:
        arr = json.loads(s[start:end + 1])
    except json.JSONDecodeError as e:
        raise PromptWriterError(f"writer reply is not valid JSON: {e}") from e
    if not isinstance(arr, list) or not all(isinstance(x, str) and x.strip() for x in arr):
        raise PromptWriterError("writer reply must be a JSON array of non-empty strings")
    if len(arr) < n:
        raise PromptWriterError(f"writer returned {len(arr)} prompts, wanted {n}")
    return [x.strip() for x in arr[:n]]


def _cli_failure(stdout: str, stderr: str) -> str:
    """The useful part of a failed `claude -p` run.

    With `--output-format json` the CLI prints a usage block first and its error message in
    `result` (or `errors`) at the end, so truncating the raw output hides the cause. Prefer
    those fields, then stderr, then the tail of stdout.
    """
    try:
        out = json.loads(stdout)
    except (json.JSONDecodeError, TypeError):
        out = None
    if isinstance(out, dict):
        parts = [str(out[k]) for k in ("result", "errors", "subtype") if out.get(k)]
        if parts:
            return " | ".join(parts)[:800]
    text = (stderr or "").strip() or (stdout or "").strip()
    return text[-800:] if text else "no output"


class ClaudeCliWriter(PromptWriter):
    """`claude -p <prompt> --output-format json`, with read access to the images' folders."""
    name = "claude-cli"
    billing = "subscription"  # the logged-in plan pays; cost.py records usd 0 and the API-equivalent figure

    def __init__(self, model: str = "claude-sonnet-5-5", command: str | None = None, timeout: int = 300) -> None:
        self.model = model
        self.command = command or os.environ.get("ASSET_CLAUDE_BIN") or "claude"
        self.timeout = timeout

    def _argv(self, prompt: str, images: list[Path]) -> list[str]:
        argv = [self.command, "-p", prompt, "--output-format", "json", "--model", self.model]
        if images:
            argv += ["--allowedTools", "Read"]
            for d in sorted({str(p.resolve().parent) for p in images}):
                argv += ["--add-dir", d]
        return argv

    def _ask(self, prompt: str, images: list[Path]) -> str:
        if images:
            prompt += "\n\nRead these image files first:\n" + "\n".join(str(p.resolve()) for p in images)
        try:
            proc = subprocess.run(self._argv(prompt, images), capture_output=True, text=True,
                                  timeout=self.timeout, stdin=subprocess.DEVNULL)
        except FileNotFoundError as e:
            raise PromptWriterError(f"claude CLI not found ({self.command!r}); install Claude Code or set ASSET_CLAUDE_BIN") from e
        except subprocess.TimeoutExpired as e:
            raise PromptWriterError(f"claude CLI timed out after {self.timeout}s") from e
        if proc.returncode != 0:
            raise PromptWriterError(f"claude CLI exited {proc.returncode}: {_cli_failure(proc.stdout, proc.stderr)}")
        try:
            out = json.loads(proc.stdout)
        except json.JSONDecodeError as e:
            raise PromptWriterError(f"claude CLI did not print JSON: {proc.stdout[:200]!r}") from e
        if isinstance(out, dict):
            usage = out.get("usage") if isinstance(out.get("usage"), dict) else {}
            self.last_usage = {k: usage[k] for k in ("input_tokens", "output_tokens") if isinstance(usage.get(k), int)}
            if isinstance(out.get("total_cost_usd"), (int, float)):
                self.last_usage["api_equivalent_usd"] = out["total_cost_usd"]
        if not isinstance(out, dict) or out.get("is_error"):
            raise PromptWriterError(f"claude CLI reported an error: {str(out.get('result', out))[:500]}")
        result = out.get("result")
        if not isinstance(result, str) or not result.strip():
            raise PromptWriterError("claude CLI JSON has no result text")
        return result

    def write_prompts(self, brief: str, style: str, notes: str, images: list[Path], n: int,
                      mode: str | None = None) -> list[str]:
        return parse_prompts(self._ask(prompts_request(brief, style, notes, n, bool(images), mode), images), n)

    def write_brief(self, context: str, images: list[Path]) -> str:
        return self._ask(brief_request(context, bool(images)), images).strip() + "\n"


class AnthropicApiWriter(PromptWriter):
    """Messages API with ANTHROPIC_API_KEY (API billing). Never uses the OAuth token."""
    name = "anthropic-api"
    env_key = "ANTHROPIC_API_KEY"

    def __init__(self, model: str = "claude-sonnet-5-5", base_url: str | None = None,
                 max_tokens: int = 4096, timeout: int = 120) -> None:
        self.model = model
        self.base_url = (base_url or os.environ.get("ANTHROPIC_BASE_URL") or "https://api.anthropic.com").rstrip("/")
        self.max_tokens = max_tokens
        self.timeout = timeout

    def _ask(self, prompt: str, images: list[Path]) -> str:
        key = os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise PromptWriterError("ANTHROPIC_API_KEY is not set (the Claude OAuth token is not accepted here)")
        content: list[dict] = []
        for p in images:
            mt = IMAGE_TYPES.get(p.suffix.lower())
            if mt is None:
                raise PromptWriterError(f"unsupported image type for {p.name}")
            content.append({"type": "image", "source": {"type": "base64", "media_type": mt,
                                                         "data": base64.b64encode(p.read_bytes()).decode()}})
        content.append({"type": "text", "text": prompt})
        body = json.dumps({"model": self.model, "max_tokens": self.max_tokens,
                           "messages": [{"role": "user", "content": content}]}).encode()
        req = urllib.request.Request(self.base_url + "/v1/messages", data=body, method="POST", headers={
            "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:500]
            raise PromptWriterError(f"Anthropic API HTTP {e.code}: {detail}") from e
        except (urllib.error.URLError, TimeoutError) as e:
            raise PromptWriterError(f"Anthropic API unreachable: {e}") from e
        except json.JSONDecodeError as e:
            raise PromptWriterError(f"Anthropic API returned invalid JSON: {e}") from e
        usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
        self.last_usage = {k: usage[k] for k in ("input_tokens", "output_tokens") if isinstance(usage.get(k), int)}
        text = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")
        if not text.strip():
            raise PromptWriterError("Anthropic API reply has no text")
        return text

    def write_prompts(self, brief: str, style: str, notes: str, images: list[Path], n: int,
                      mode: str | None = None) -> list[str]:
        return parse_prompts(self._ask(prompts_request(brief, style, notes, n, bool(images), mode), images), n)

    def write_brief(self, context: str, images: list[Path]) -> str:
        return self._ask(brief_request(context, bool(images)), images).strip() + "\n"


REGISTRY["prompt_writer"]["claude-cli"] = ClaudeCliWriter
REGISTRY["prompt_writer"]["anthropic-api"] = AnthropicApiWriter
