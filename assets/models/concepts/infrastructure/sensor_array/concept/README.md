# Sensor array: concept art

The first unmanned site (#927): a listening array on the seabed. A ribbed concrete node vault on a plinth with a
beacon mast, six sensor posts fanned in front of it, armoured cables on the seabed. Locked by Tristan on 2026-11-28
("a good place to start").

| File | View | Lineage |
| --- | --- | --- |
| `sensor_array_primary.png` | Three-quarter: the whole site, the sub hovering at the node | v7, a refine of v2, a paint-over of the greybox camera `three_quarter` |
| `sensor_array_overview.png` | Overview: the cable fan from the node | v8, a refine of v5, a paint-over of `overview` |
| `sensor_array_node_detail.png` | A diver at the node: hatches under amber lamps, a work light, the cut cable | v3, a paint-over of `node_diver` |
| `sensor_array_post_detail.png` | A diver at a post: the pod hatch at working height | v4, a paint-over of `post_diver` |

Each is painted over the greybox built from the site layout (`assets/models/facilities/sensor_array/`:
`program.yaml`, checked and drawn by `tools/facility_plan/site.py`, greyboxed by `tools/facility_plan/blockout.py`;
the greybox renders are in its `renders/blockout/`) and keeps its camera.

Lesson: in wide shots, where the site is small in frame, the image model invents structures (giant posts, extra
buildings, classical columns). A refine whose notes list exactly what the site contains, and forbid additions, brings
it back.
