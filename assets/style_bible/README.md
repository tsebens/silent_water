# Style bible

Input to the asset pipeline (concept #222). Seeded from `docs/art_direction.md`, which wins on any disagreement.

| File | Purpose |
| --- | --- |
| `style.md` | Canonical prompt block, prepended to every concept prompt |
| `negative.md` | Negative prompt block, appended to every concept prompt |
| `anchors/<class>/` | Approved anchor images (2-4 per class), passed as references on every concept call. Empty until Tristan approves some |
| `classes.yaml` | Per-class profile (below) |

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
