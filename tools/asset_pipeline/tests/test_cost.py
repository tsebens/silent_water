"""The cost ledger: usage extraction per adapter from recorded fixtures, pricing, append-only behaviour."""
import json
import re
from pathlib import Path

import pytest
import yaml

from asset_pipeline import cli, cost, paths, providers
from asset_pipeline.adapters._net import ImageProviderError
from asset_pipeline.adapters.fal_image import FalImage
from asset_pipeline.adapters.google_image import GoogleImage
from asset_pipeline.adapters.openai_image import OpenAIImage
from asset_pipeline.manifest import Manifest
from asset_pipeline.writers import AnthropicApiWriter, ClaudeCliWriter
from test_image_adapters import Stub, server  # noqa: F401  (the recorded-response server fixture)
from test_writers import Recorder, stub_claude
from test_writers import server as anthropic_server  # noqa: F401

FIX = Path(__file__).parent / "fixtures"
PRICES = cost.load_prices(FIX / "prices.yaml")


def ledger(prov, kind="image", **kw):
    return cost.entry_for(prov, kind, PRICES, command="concept", stage="concept", **kw)


# ---- one recorded response per adapter -------------------------------------------------------

def test_openai_usage_is_priced_from_tokens(server, tmp_path, monkeypatch):  # noqa: F811
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    Stub.fixture = "openai_images_response.json"
    p = OpenAIImage(base_url=server)
    p.generate("x", [], tmp_path / "a.png")
    e = ledger(p)
    assert e.units == {"input_tokens": 40, "output_tokens": 60, "total_tokens": 100, "images": 1}
    assert e.basis == "estimated" and e.usd == pytest.approx(0.0026)  # 40*5/1e6 + 60*40/1e6
    assert e.unit_price == {"usd_per_mtok_input": 5.0, "usd_per_mtok_output": 40.0}


def test_google_usage_is_priced_from_tokens(server, tmp_path, monkeypatch):  # noqa: F811
    monkeypatch.setenv("GEMINI_API_KEY", "k")
    Stub.fixture = "google_generate_response.json"
    p = GoogleImage(base_url=server)
    p.generate("x", [], tmp_path / "a.png")
    e = ledger(p)
    assert e.units == {"input_tokens": 120, "output_tokens": 180, "total_tokens": 300, "images": 1}
    assert e.basis == "estimated" and e.usd == pytest.approx(0.00192)


def test_fal_is_priced_per_image(server, tmp_path, monkeypatch):  # noqa: F811
    monkeypatch.setenv("FAL_KEY", "k")
    Stub.fixture = "fal_response.json"
    p = FalImage(base_url=server)
    p.generate("x", [], tmp_path / "a.png")
    e = ledger(p)
    assert e.units == {"images": 1} and e.basis == "estimated" and e.usd == pytest.approx(0.04)
    assert e.unit_price == {"usd_per_image": 0.04}


def test_claude_cli_is_subscription_with_api_equivalent(tmp_path):
    cmd, _ = stub_claude(tmp_path, (FIX / "claude_cli_response.json").read_text())
    w = ClaudeCliWriter(command=cmd)
    w.write_prompts("b", "s", "", [], 2)
    e = ledger(w, "prompt_writer")
    assert e.basis == "subscription" and e.usd == 0.0
    assert e.api_equivalent_usd == 0.0123 and e.units == {"input_tokens": 1200, "output_tokens": 80}
    assert e.unit_price == {}


def test_anthropic_api_is_priced_from_token_usage(anthropic_server, monkeypatch):  # noqa: F811
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k")
    w = AnthropicApiWriter(base_url=anthropic_server)
    w.write_prompts("b", "s", "", [], 2)
    e = ledger(w, "prompt_writer")
    assert e.units == {"input_tokens": 812, "output_tokens": 47}
    assert e.basis == "estimated" and e.usd == pytest.approx(0.003141)
    assert e.unit_price == {"usd_per_mtok_input": 3.0, "usd_per_mtok_output": 15.0}


# ---- billed failures, mock, unknown, credits -------------------------------------------------

def test_failed_but_billed_call_is_recorded(server, tmp_path, monkeypatch):  # noqa: F811
    """A reply with usage but no image (e.g. blocked output) was charged: it is recorded, then the error propagates."""
    monkeypatch.setenv("GEMINI_API_KEY", "k")
    reply = json.loads((FIX / "google_generate_response.json").read_text())
    del reply["candidates"]
    reply["promptFeedback"] = {"blockReason": "SAFETY"}
    (tmp_path / "blocked.json").write_text(json.dumps(reply))
    Stub.fixture = str(tmp_path / "blocked.json")  # FIX / <absolute path> is the absolute path
    p = GoogleImage(base_url=server)
    m = Manifest(slug="a", asset_class="creature")
    with pytest.raises(ImageProviderError, match="no image"):
        cost.paid_call(m, p, "image", PRICES, lambda: p.generate("x", [], tmp_path / "a.png"), command="concept", stage="concept")
    assert len(m.costs) == 1 and m.costs[0].error and m.costs[0].usd == pytest.approx(0.00192)


def test_unbilled_failure_records_nothing(server, tmp_path, monkeypatch):  # noqa: F811
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    Stub.status = 401
    p = OpenAIImage(base_url=server)
    m = Manifest(slug="a", asset_class="creature")
    with pytest.raises(ImageProviderError):
        cost.paid_call(m, p, "image", PRICES, lambda: p.generate("x", [], tmp_path / "a.png"), command="concept", stage="concept")
    assert m.costs == []


def test_mock_records_zero_with_basis_mock(tmp_path):
    p = providers.MockImageProvider()
    m = Manifest(slug="a", asset_class="creature")
    cost.paid_call(m, p, "image", PRICES, lambda: p.generate("x", [], tmp_path / "a.png"),
                   command="concept", stage="concept", lineage="v1")
    assert (m.costs[0].usd, m.costs[0].basis, m.costs[0].lineage) == (0.0, "mock", "v1")


def test_unpriceable_call_is_unknown_with_null_usd(server, tmp_path, monkeypatch):  # noqa: F811
    monkeypatch.setenv("FAL_KEY", "k")
    Stub.fixture = "fal_response.json"
    p = FalImage(model="fal-ai/not-in-the-table", base_url=server)
    p.generate("x", [], tmp_path / "a.png")
    e = ledger(p)
    assert e.usd is None and e.basis == "unknown" and e.units == {"images": 1}
    # a priced model whose reply carried no usable figure is unknown too, never 0
    assert cost.compute({"usd_per_mtok_input": 3.0}, {"images": 1}) == (None, "unknown", {})


def test_credits_are_reported_and_provider_cost_wins():
    price = PRICES["three_d"]["tripo"]["v3.1-20260211"]
    assert cost.compute(price, {"credits": 30}) == (0.3, "reported", {"usd_per_credit": 0.01})
    assert cost.compute(price, {}, reported_usd=0.5) == (0.5, "reported", {})


# ---- the ledger in a manifest ----------------------------------------------------------------

def test_ledger_round_trips_with_null_usd_and_posix_paths(tmp_path):
    m = Manifest(slug="a", asset_class="creature")
    m.costs.append(cost.CostEntry(command="to3d", stage="to3d", provider="x", model="y", usd=None, basis="unknown"))
    m.save(tmp_path / "a" / "asset.yaml")
    back = Manifest.load(tmp_path / "a" / "asset.yaml")
    assert back.costs[0].usd is None and back.costs[0].basis == "unknown"


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def test_reject_and_regenerate_keep_earlier_entries(root, capsys):
    run(capsys, "new", "eel", "--class", "creature", "--description", "an eel")
    run(capsys, "concept", "eel", "--n", "2")
    mpath = paths.manifest_path(root, "eel")
    before = Manifest.load(mpath).costs
    assert [(c.command, c.basis) for c in before] == [("concept", "mock")] * 3  # one writer call + two images
    assert [c.lineage for c in before] == [None, "v1", "v2"]
    run(capsys, "lock", "eel", "v1", "--reviewer", "t")
    run(capsys, "lock", "eel", "v2", "--decision", "rejected", "--reviewer", "t")
    run(capsys, "turnaround", "eel")
    run(capsys, "turnaround", "eel", "--view", "left")
    after = Manifest.load(mpath).costs
    assert after[:3] == before  # untouched by the reject and the regenerate
    assert [c.lineage for c in after[3:]] == ["t1_front", "t1_left", "t1_back", "t1_right", "t2_left"]
    assert cost.total_usd(Manifest.load(mpath)) == 0.0


def test_a_failed_command_still_saves_the_spend(root, capsys, monkeypatch):
    run(capsys, "new", "eel", "--class", "creature", "--description", "an eel")
    calls = []
    real = providers.MockImageProvider.generate

    def flaky(self, prompt, refs, out):
        calls.append(1)
        if len(calls) == 2:
            raise ImageProviderError("boom")
        return real(self, prompt, refs, out)

    monkeypatch.setattr(providers.MockImageProvider, "generate", flaky)
    assert cli.main(["concept", "eel", "--n", "2"]) == 1
    capsys.readouterr()
    m = Manifest.load(paths.manifest_path(root, "eel"))
    assert [c.lineage for c in m.costs] == [None, "v1"]  # the writer and the first image that did succeed


def test_claude_cli_never_counts_as_spend():
    m = Manifest(slug="a", asset_class="creature")
    m.costs += [cost.CostEntry(command="c", stage="concept", provider="claude-cli", model="m", usd=0.0,
                               basis="subscription", api_equivalent_usd=1.5),
                cost.CostEntry(command="c", stage="concept", provider="openai", model="m", usd=0.25, basis="estimated"),
                cost.CostEntry(command="c", stage="concept", provider="fal", model="m", usd=None, basis="unknown")]
    assert cost.total_usd(m) == 0.25


# ---- prices.yaml -----------------------------------------------------------------------------

def test_real_prices_cover_every_configured_provider_model():
    prices, cfg = cost.load_prices(), providers.load_config()
    for kind, entries in cfg["providers"].items():
        for name, entry in entries.items():
            model = (entry or {}).get("model")
            if name in ("mock", "claude-cli") or not model:
                continue
            assert cost.price_for(prices, kind, name, model), f"no price for {kind}/{name}/{model}"


def test_every_price_has_source_and_date():
    for kind in ("image", "prompt_writer", "three_d"):
        for models in cost.load_prices()[kind].values():
            for model, price in models.items():
                assert price.get("source", "").startswith("http") and price.get("checked"), model


def test_every_credit_price_has_a_plan_comment():
    lines = cost.PRICES_PATH.read_text().splitlines()
    credit_lines = [i for i, ln in enumerate(lines) if re.match(r"\s*usd_per_credit:", ln)]
    assert len(credit_lines) >= 3  # tripo, meshy, rodin
    for i in credit_lines:
        prev = lines[i - 1].strip()
        assert prev.startswith("#") and "plan" in prev.lower(), f"line {i + 1}: usd_per_credit needs a comment naming the plan"
    credit_providers = {p for p, ms in cost.load_prices()["three_d"].items()
                        if any("usd_per_credit" in v for v in ms.values())}
    assert {"tripo", "meshy", "rodin"} <= credit_providers
