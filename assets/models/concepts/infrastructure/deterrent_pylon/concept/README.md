# Deterrent pylon: concept art

An unmanned site (#927) that mimics the apex's call: lesser predators flee it, the apex comes to it. A ribbed concrete
column on a buttressed plinth, a ring of amber lamps (the cell's charge gauge), an emitter drum of transducers, a
receiver mast, and the cell bay and arming panel at a diver's working height. Switched on and off from the sub's
countermeasures station. Locked by Tristan on 2026-11-28.

| File | View | Lineage |
| --- | --- | --- |
| `deterrent_pylon_primary.png` | Looking up from its foot | v7, a refine of v3, a paint-over of the greybox camera `from_below` |
| `deterrent_pylon_approach.png` | The approach, the sub alongside | v1, a paint-over of `approach` |
| `deterrent_pylon_front.png` | From the front | v5, a paint-over of `overview` (the image model moved the camera) |
| `deterrent_pylon_three_quarter.png` | Three-quarter | v6, a refine of v2, a paint-over of `three_quarter` |
| `deterrent_pylon_service_detail.png` | A diver at the cell bay and arming panel | v4, a paint-over of `diver_service` |

Layout: `assets/models/facilities/deterrent_pylon/program.yaml` (checked by `tools/facility_plan/site.py`); greybox
renders in its `renders/blockout/`.

Lessons: a solid glowing band just under the dark emitter drum read as a face; the lamp ring is drawn as separate lamps
on a slim collar (the greybox now does so too). In wide and low shots the image model invented cross-arms and floating
blocks; a refine listing exactly what the site contains removed them.
