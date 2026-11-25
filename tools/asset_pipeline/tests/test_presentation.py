"""asset concept --presentation subject|scene."""
import json
import shutil
from pathlib import Path

import yaml

from asset_pipeline import cli, paths
from asset_pipeline.manifest import Manifest

REPO = Path(__file__).resolve().parents[3]
SUBJECT_STYLE = "Presentation: one subject, centred, on a plain neutral dark-grey background."


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def seed(root, capsys, scene_default=False):
    sb = root / "assets" / "style_bible"
    (sb / "anchors" / "prop").mkdir(parents=True)
    (sb / "anchors" / "interior").mkdir(parents=True)
    (sb / "style.md").write_text(f"SHARED\n\n{SUBJECT_STYLE}\n\n## presentation_scene\nPresentation: SCENE RULES\n")
    (sb / "negative.md").write_text("- people, hands\n- cluttered background\n\n## presentation_scene\n- SCENE NEG\n")
    (sb / "classes.yaml").write_text(yaml.safe_dump({"classes": {
        "prop": {"concept_presentation": "scene"} if scene_default else {}, "interior": {"concept_presentation": "scene"}}}))
    run(capsys, "new", "thing", "--class", "prop")
    run(capsys, "new", "cabin", "--class", "interior")


def prompt(root, slug, vid="v1"):
    return Manifest.load(paths.manifest_path(root, slug)).entry(vid).prompt


def test_subject_prompt_is_unchanged(root, capsys):
    seed(root, capsys)
    run(capsys, "concept", "thing", "--n", "1", "--brief", "a lamp")
    p = prompt(root, "thing")
    assert p.startswith(f"SHARED\n\n{SUBJECT_STYLE}\n\n[mock ")
    assert p.endswith("\n\nAvoid:\n- people, hands\n- cluttered background")
    assert "SCENE" not in p
    m = Manifest.load(paths.manifest_path(root, "thing"))
    assert m.entry("v1").presentation == "subject"


def test_scene_swaps_presentation_and_negatives(root, capsys):
    seed(root, capsys)
    code, out = run(capsys, "concept", "thing", "--n", "1", "--brief", "a lamp", "--presentation", "scene")
    assert code == 0 and out["variants"][0]["presentation"] == "scene"
    p = prompt(root, "thing")
    assert "SCENE RULES" in p and "SCENE NEG" in p and p.startswith("SHARED\n\nPresentation: SCENE RULES")
    assert "plain neutral dark-grey background" not in p
    assert "people, hands" not in p and "cluttered background" not in p
    assert Manifest.load(paths.manifest_path(root, "thing")).entry("v1").presentation == "scene"


def test_scene_reaches_the_writer(root, capsys, monkeypatch):
    seed(root, capsys)
    from asset_pipeline import providers
    seen = []
    orig = providers.MockPromptWriter.write_prompts

    def spy(self, brief, style, *a, **k):
        seen.append(style)
        return orig(self, brief, style, *a, **k)

    monkeypatch.setattr(providers.MockPromptWriter, "write_prompts", spy)
    run(capsys, "concept", "thing", "--n", "1", "--brief", "b", "--presentation", "scene")
    assert "SCENE RULES" in seen[0] and "plain neutral" not in seen[0]


def test_refine_inherits_presentation(root, capsys):
    seed(root, capsys)
    run(capsys, "concept", "thing", "--n", "1", "--brief", "b", "--presentation", "scene")
    run(capsys, "concept", "thing", "--n", "1", "--refine", "v1", "--notes", "warmer")
    assert prompt(root, "thing", "v2").count("SCENE RULES") == 1
    assert Manifest.load(paths.manifest_path(root, "thing")).entry("v2").presentation == "scene"


def test_refine_of_legacy_variant_stays_subject(root, capsys):
    seed(root, capsys, scene_default=True)
    run(capsys, "concept", "thing", "--n", "1", "--brief", "b", "--presentation", "subject")
    mp = paths.manifest_path(root, "thing")
    m = Manifest.load(mp)
    m.entry("v1").presentation = ""
    m.save(mp)
    run(capsys, "concept", "thing", "--n", "1", "--refine", "v1", "--notes", "n")
    assert Manifest.load(mp).entry("v2").presentation == "subject"


def test_class_default_and_flag_override(root, capsys):
    seed(root, capsys)
    run(capsys, "concept", "cabin", "--n", "1", "--brief", "a cabin")
    assert "SCENE RULES" in prompt(root, "cabin")
    run(capsys, "concept", "cabin", "--n", "1", "--presentation", "subject")
    p = prompt(root, "cabin", "v2")
    assert "SCENE" not in p and "plain neutral dark-grey background" in p


def test_old_manifest_without_field_loads(root, capsys):
    seed(root, capsys)
    run(capsys, "concept", "thing", "--n", "1", "--brief", "b")
    mp = paths.manifest_path(root, "thing")
    data = yaml.safe_load(mp.read_text())
    for e in data["lineage"]:
        e.pop("presentation", None)
    mp.write_text(yaml.safe_dump(data))
    assert Manifest.load(mp).entry("v1").presentation == ""


def test_real_style_bible_scene_rules():
    sb = REPO / "assets" / "style_bible"
    style, scene = cli.split_scene((sb / "style.md").read_text())
    assert "plain neutral dark-grey background" in style and "presentation_scene" not in style
    assert scene and "plain neutral" not in scene
    neg, sneg = cli.split_scene((sb / "negative.md").read_text())
    assert "people, hands" in neg and sneg and "people" not in sneg
