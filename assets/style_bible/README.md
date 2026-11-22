# Style bible

Input to the asset pipeline (concept #222). Seeded from `docs/art_direction.md`, which wins on any disagreement.

| File | Purpose |
| --- | --- |
| `style.md` | Shared style block, true for every class, prepended to every prompt |
| `negative.md` | Shared negative list, true for every class, appended to every prompt |
| `classes/<class>.md` | Per-class `## Style` and `## Avoid` sections (below) |
| `anchors/<class>/` | Approved anchor images (2-4 per class), passed as references on every concept call. Empty until Tristan approves some |
| `classes.yaml` | Per-class profile (below) |

## Class files

`classes/<class>.md` exists for each class in `classes.yaml` and has two sections, `## Style` (prose) and `## Avoid` (a bullet list). `concept`, `turnaround` and `brief` use the asset's class and assemble the prompt as: shared style, class style, the prompt writer's text, shared negative, class negative. The shared files hold only what applies to every class; anything specific to one class goes in its file. `tools/validate_style_bible.py` fails when a class file or either section is missing.

## `classes.yaml` format

Top-level key `classes`, with one entry each for `creature`, `prop`, `terrain`, `architecture`. Fields:

| Field | Meaning |
| --- | --- |
| `build_route` | `image-to-3d` or `scripted` |
| `triangle_budget` | Maximum triangles after cleanup |
| `scale_range_m` | `[min, max]` largest dimension in metres |
| `snap_grid_m` | Snap grid in metres, or `null` when the class has none |
| `palette_size` | Maximum distinct vertex colours |
| `cleanup_recipe` | Ordered list of cleanup step names |
| `gates` | Thresholds: `triangle_tolerance` (multiplier on budget), `bbox_tolerance` (fraction), `max_loose_parts`, `max_non_manifold`, `silhouette_iou_min` (0 to 1) |

`tools/validate_style_bible.py` checks this shape and runs from `tools/check.sh`.
