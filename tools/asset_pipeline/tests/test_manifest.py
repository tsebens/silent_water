import pytest

from asset_pipeline.manifest import LineageEntry, Manifest


def entry(i, parent=None, kind="concept"):
    return LineageEntry(id=i, kind=kind, path=f"{i}.png", provider="mock", model="m", prompt=f"p {i}", parent=parent)


def test_round_trip(tmp_path):
    m = Manifest(slug="angler", asset_class="creature", issue=7)
    m.add(entry("v1"))
    m.add(entry("v2", parent="v1"))
    m.lock("v2", reviewer="tristan", notes="best")
    p = tmp_path / "asset.yaml"
    m.save(p)
    assert Manifest.load(p) == m


def test_lineage_ancestry():
    m = Manifest(slug="a", asset_class="prop")
    m.add(entry("v1"))
    m.add(entry("v2", parent="v1"))
    m.add(entry("v3", parent="v2"))
    assert m.ancestry("v3") == ["v3", "v2", "v1"]


def test_lineage_rejects_missing_parent_and_duplicates():
    m = Manifest(slug="a", asset_class="prop")
    with pytest.raises(KeyError):
        m.add(entry("v2", parent="nope"))
    m.add(entry("v1"))
    with pytest.raises(ValueError):
        m.add(entry("v1"))


def test_lock_records_decision():
    m = Manifest(slug="a", asset_class="prop")
    m.add(entry("v1"))
    m.add(entry("mesh1", kind="mesh"))
    with pytest.raises(ValueError):
        m.lock("mesh1", reviewer="t")
    with pytest.raises(KeyError):
        m.lock("zzz", reviewer="t")
    m.lock("v1", reviewer="t", decision="rejected")
    assert m.locked is None and m.stage == "new" and m.decisions[0].decision == "rejected"
    m.lock("v1", reviewer="t")
    assert m.locked.variant == "v1" and m.locked.decision == "approved" and m.stage == "locked"
    m.add(entry("v2"))
    m.lock("v2", reviewer="t")
    assert m.locked.variant == "v2"
    assert [(d.variant, d.decision) for d in m.decisions] == [("v1", "rejected"), ("v1", "approved"), ("v2", "approved")]
