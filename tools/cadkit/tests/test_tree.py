"""The real tree: every generated file in the repository is what its build script makes."""
from cadkit import build, catalogue


def test_the_repository_tree_is_in_sync_with_its_build_scripts():
    out = build.run("verify")
    assert out["ok"], "\n".join(out.get("problems", [])) or out.get("error")


def test_every_generated_scene_has_a_complete_catalogue_entry():
    cat = catalogue.load()
    assert cat["generated"], "no generated scenes found"
    for e in cat["generated"]:
        for field in ("slug", "group", "kind", "summary", "tags", "built_by", "files", "triangles"):
            assert field in e or (field == "triangles" and "sizes" in e), f"{e.get('slug')}: no {field}"
        if e["kind"] != "solid_set":
            assert "mount" in e and "scene" in e, f"{e['slug']}: a scene's entry says how it mounts"


def test_catalogue_search_matches_all_words():
    cat = catalogue.search(catalogue.load(), ["toggle", "guarded"])
    slugs = [e["slug"] for e in cat["generated"]]
    assert "guarded_toggle" in slugs
    assert "indicator_lamp" not in slugs, "an entry matching only one word is excluded"
