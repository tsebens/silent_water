# cadkit

Builds Silent Water's mechanical assets. Agents write one parametric CAD script per scene (build123d); cadkit turns
the solids into flat-shaded GLBs with palette vertex colours, writes the Godot scene that assembles them, and keeps a
catalogue of what exists. The process it serves, and the rules for using it, are in
[`docs/asset_process.md`](../../docs/asset_process.md).

```
uv run cadkit catalogue              # the asset library, read fresh (add words to search, --json for full entries)
uv run cadkit check                  # build everything in a staging folder; write nothing
uv run cadkit build                  # the same, then write the result if every scene passed
uv run cadkit verify                 # the same, then report generated files that are stale or hand-edited
uv run cadkit render <slug>          # PNGs into build/renders/<slug>/ (needs Godot; xvfb-run if no display)
uv run cadkit sheet <slug>           # review sheets into <scene>/review/
uv run pytest                        # the tooling's tests, and that the repository tree is in sync
```

## Layout

| Path | What |
| --- | --- |
| `scenes/<slug>.py` | One build script per scene: `SLUG`, `GROUP`, `USES`, `build()`. No list anywhere; the build order comes from `USES` |
| `cadkit/solids.py` | Shapes (`box`, `prism`, `at`), checks (`expect`, `expect_in_front`), GLB export |
| `cadkit/tscn.py` | A small `.tscn` writer |
| `cadkit/library.py` | Where scenes live, catalogue entries, the 60 mm panel module, the palette |
| `cadkit/build.py` | Discover, stage, promote, verify |
| `cadkit/catalogue.py`, `catalogue/existing.yaml` | The catalogue: generated entries, plus hand-built scenes and control behaviours |
| `cadkit/render.py` | Rendering through `tests/scene_shot.tscn`, and review sheets |

Output goes to `assets/models/<group>/<slug>/`: GLBs, the `.tscn`, `component.yaml` (the catalogue entry, which also
lists the files the build generated) and `review/`.

## Notes

- build123d is pinned (0.13.0): its API moves between minor versions, and a model's training data is older than the
  installed library. Read an existing scene script before writing one.
- A build is all or nothing and always covers the whole tree (a few seconds). Unchanged scenes come out byte-identical.
- The environment is about 840 MB, nearly all the OCCT kernel. It is separate from `tools/asset_pipeline` so that
  Asset Studio users don't pay for it.
- Blender is not needed. The game's tests need only Godot, because the GLBs are committed.
