"""`asset cost`, `asset cost --all`, `--estimate` and the soft budget."""
import json

import pytest
import yaml

from asset_pipeline import cli, cost, paths, providers
from asset_pipeline.manifest import CostRecord, Manifest

FIX = __import__("pathlib").Path(__file__).parent / "fixtures"
PRICES = cost.load_prices(FIX / "prices.yaml")


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def c(stage, provider, usd, basis, command="x"):
    return CostRecord(command=command, stage=stage, provider=provider, model="m", usd=usd, basis=basis)


def make(root, slug, costs, cls="prop", budget=None):
    m = Manifest(slug=slug, asset_class=cls, costs=costs, budget_usd=budget)
    m.save(paths.manifest_path(root, slug))
    return m


def set_class_budget(root, value):
    f = root / "assets" / "style_bible" / "classes.yaml"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(yaml.safe_dump({"classes": {"prop": {"budget_usd": value}, "creature": {}}}))


LEDGER = [c("concept", "openai", 0.30, "estimated"), c("concept", "mock", 0.0, "mock"),
          c("to3d", "tripo", 0.50, "reported"), c("to3d", "tripo", 0.25, "reported"),
          c("to3d", "meshy", None, "unknown"), c("brief", "claude-cli", 0.0, "subscription")]


def test_cost_splits_reported_estimated_and_lists_unknown(root, capsys):
    make(root, "rock", LEDGER)
    code, out = run(capsys, "cost", "rock")
    assert code == 0
    assert out["total_usd"] == 1.05 and out["reported_usd"] == 0.75 and out["estimated_usd"] == 0.30
    assert out["by_stage"]["to3d"] == {"usd": 0.75, "count": 3, "unknown": 1}
    assert out["by_stage"]["concept"]["count"] == 2
    assert out["by_provider"]["tripo"] == {"usd": 0.75, "count": 2, "unknown": 0}
    assert "claude-cli" not in out["by_provider"]  # subscription is never spend
    assert [u["provider"] for u in out["unknown"]] == ["meshy"]
    assert "warning" not in out


def test_cost_all_gives_per_asset_and_grand_totals(root, capsys):
    make(root, "rock", LEDGER)
    make(root, "kelp", [c("concept", "fal", 0.04, "estimated")])
    code, out = run(capsys, "cost", "--all")
    assert code == 0
    assert [a["slug"] for a in out["assets"]] == ["kelp", "rock"]
    assert out["total_usd"] == 1.09 and out["reported_usd"] == 0.75 and out["estimated_usd"] == 0.34
    assert out["unknown"] == 1


def test_cost_needs_a_slug_or_all(root, capsys):
    code, out = run(capsys, "cost")
    assert code == 1 and "--all" in out["error"]


def test_budget_warning_above_threshold_only(root, capsys):
    set_class_budget(root, 1.0)
    make(root, "rock", LEDGER)  # 1.05 spent
    assert "warning" in run(capsys, "cost", "rock")[1]
    make(root, "rock", LEDGER, budget=None)
    set_class_budget(root, 1.05)  # at the limit is not over it
    assert "warning" not in run(capsys, "cost", "rock")[1]
    set_class_budget(root, 5.0)
    assert "warning" not in run(capsys, "cost", "rock")[1]


def test_asset_budget_overrides_class_budget(root, capsys):
    set_class_budget(root, 100.0)
    make(root, "rock", LEDGER, budget=0.5)
    code, out = run(capsys, "cost", "rock")
    assert out["budget_usd"] == 0.5 and "warning" in out and code == 0  # warns, blocks nothing
    set_class_budget(root, 0.1)
    make(root, "rock", LEDGER, budget=50.0)
    assert "warning" not in run(capsys, "cost", "rock")[1]
    assert run(capsys, "cost", "--all")[1]["warnings"] == []


# ---- --estimate ------------------------------------------------------------------------------

@pytest.fixture
def priced(monkeypatch):
    monkeypatch.setattr(cost, "load_prices", lambda path=None: PRICES)
    cfg = providers.load_config()
    cfg["selection"]["image"] = "openai"
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    monkeypatch.setattr(providers, "load_config", lambda *a, **k: cfg)
    return cfg


def test_estimate_concept_n3_is_three_images_and_calls_nothing(root, capsys, priced):
    make(root, "rock", [])
    before = paths.manifest_path(root, "rock").read_text()
    code, out = run(capsys, "concept", "rock", "--n", "3", "--estimate")  # the network guard fails any live call
    assert code == 0 and out["estimate"]["usd"] == pytest.approx(0.3)  # 3 x usd_per_image 0.1; mock writer is free
    kinds = {x["kind"]: x for x in out["estimate"]["calls"]}
    assert kinds["image"]["count"] == 3 and kinds["prompt_writer"]["basis"] == "mock"
    assert paths.manifest_path(root, "rock").read_text() == before


def test_estimate_two_provider_to3d(root, capsys, priced):
    make(root, "rock", [])
    code, out = run(capsys, "to3d", "rock", "--3d-provider", "meshy", "tripo", "--estimate")
    # meshy 30 credits x 0.02 = 0.60 (tripo has no credits_per_generation in the table: unknown, not zero)
    assert code == 0 and out["estimate"]["usd"] == pytest.approx(0.6)
    assert [u["provider"] for u in out["estimate"]["unknown"]] == ["tripo"]


def test_estimate_turnaround_and_single_view(root, capsys, priced):
    make(root, "rock", [])
    assert run(capsys, "turnaround", "rock", "--estimate")[1]["estimate"]["usd"] == pytest.approx(0.4)
    assert run(capsys, "turnaround", "rock", "--view", "left", "--estimate")[1]["estimate"]["usd"] == pytest.approx(0.1)


def test_estimate_of_a_paid_writer_lists_it_as_unknown(root, capsys, priced, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k")
    make(root, "rock", [])
    code, out = run(capsys, "brief", "rock", "--prompt-writer", "anthropic-api", "--estimate")
    assert code == 0 and out["estimate"]["usd"] == 0 and len(out["estimate"]["unknown"]) == 1
