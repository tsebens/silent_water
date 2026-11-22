"""Shared HTTP plumbing for the hosted image adapters: JSON and multipart POST, GET, error mapping."""
from __future__ import annotations

import base64
import json
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any

IMAGE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}


class ImageProviderError(ValueError):
    """A hosted image provider could not produce an image (missing key, HTTP failure, bad reply)."""


def mime_of(p: Path) -> str:
    mt = IMAGE_TYPES.get(p.suffix.lower())
    if mt is None:
        raise ImageProviderError(f"unsupported image type for {p.name}")
    return mt


def b64_of(p: Path) -> str:
    return base64.b64encode(p.read_bytes()).decode()


def data_uri(p: Path) -> str:
    return f"data:{mime_of(p)};base64,{b64_of(p)}"


def _reason(status: int) -> str:
    if status in (401, 403):
        return "authentication failed (check the API key)"
    if status == 429:
        return "rate limited or out of quota"
    if status in (400, 404, 422):
        return "request rejected"
    if status >= 500:
        return "provider server error"
    return "unexpected response"


def _detail(raw: bytes) -> str:
    text = raw.decode(errors="replace")
    try:
        err = json.loads(text)
        e = err.get("error", err.get("detail", err)) if isinstance(err, dict) else err
        if isinstance(e, dict):
            e = e.get("message", e)
        text = e if isinstance(e, str) else json.dumps(e)
    except json.JSONDecodeError:
        pass
    return text.strip()[:400]


def request(provider: str, url: str, headers: dict[str, str], body: bytes | None = None,
            timeout: int = 180, ok_status: tuple[int, ...] = ()) -> bytes:
    """One HTTP call. HTTP and network failures become ImageProviderError naming the provider.
    Statuses in `ok_status` return their body instead of raising (used by liveness checks)."""
    req = urllib.request.Request(url, data=body, headers=headers, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        raw = e.read()
        if e.code in ok_status:
            return raw
        raise ImageProviderError(f"{provider} HTTP {e.code}: {_reason(e.code)}: {_detail(raw)}") from e
    except (urllib.error.URLError, TimeoutError) as e:
        raise ImageProviderError(f"{provider} unreachable: {e}") from e


def post_json(provider: str, url: str, headers: dict[str, str], payload: dict[str, Any], timeout: int = 180) -> Any:
    raw = request(provider, url, {**headers, "content-type": "application/json"},
                  json.dumps(payload).encode(), timeout)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise ImageProviderError(f"{provider} returned invalid JSON: {e}") from e


def multipart(fields: dict[str, str], files: list[tuple[str, Path]]) -> tuple[bytes, str]:
    """Encode a multipart/form-data body; returns (body, content-type)."""
    boundary = uuid.uuid4().hex
    out = b""
    for k, v in fields.items():
        out += (f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n').encode()
    for k, p in files:
        out += (f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{p.name}"\r\n'
                f"Content-Type: {mime_of(p)}\r\n\r\n").encode() + p.read_bytes() + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return out, f"multipart/form-data; boundary={boundary}"


def post_multipart(provider: str, url: str, headers: dict[str, str], fields: dict[str, str],
                   files: list[tuple[str, Path]], timeout: int = 180) -> Any:
    body, ctype = multipart(fields, files)
    raw = request(provider, url, {**headers, "content-type": ctype}, body, timeout)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise ImageProviderError(f"{provider} returned invalid JSON: {e}") from e


def token_usage(usage: Any, keys: tuple[str, ...], names: tuple[str, ...] | None = None) -> dict[str, Any]:
    """Usage of one image call for the cost ledger: the token counts the reply reported (renamed to `names`)
    plus the one image requested. Counts the reply did not carry are left out, never zero."""
    out: dict[str, Any] = {}
    if isinstance(usage, dict):
        for k, name in zip(keys, names or keys):
            if isinstance(usage.get(k), int) and not isinstance(usage.get(k), bool):
                out[name] = usage[k]
    out["images"] = 1
    return out


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def write_image(out: Path, data: bytes) -> Path:
    """Save a provider's image bytes as a real PNG at `out`.

    Providers return whatever format they choose (Nano Banana sends JPEG, others WebP), but the
    pipeline names every image `.png` and the gates read 8-bit PNG, so anything that is not
    already PNG is decoded and re-encoded. Bytes that are not an image at all are an error.
    """
    if not data:
        raise ImageProviderError("provider returned an empty image")
    out.parent.mkdir(parents=True, exist_ok=True)
    if data.startswith(PNG_SIGNATURE):
        out.write_bytes(data)
        return out
    import io

    from PIL import Image, UnidentifiedImageError

    try:
        with Image.open(io.BytesIO(data)) as img:
            img.load()
            mode = "RGBA" if img.mode in ("RGBA", "LA", "P", "PA") or "transparency" in img.info else "RGB"
            img.convert(mode).save(out, format="PNG")
    except UnidentifiedImageError as exc:
        head = data[:60].decode("utf-8", "replace")
        raise ImageProviderError(f"provider returned data that is not an image: {head!r}") from exc
    return out
