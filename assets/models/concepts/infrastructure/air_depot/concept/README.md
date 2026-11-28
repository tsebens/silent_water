# Air depot: concept art

An unmanned site (#927): "a little underwater gas station" (Tristan). The sub docks under a collar on a gantry arm;
a diver goes out and turns the fill valves by hand at the valve house while O2, ballast air and charge flow in. A tank
yard of three gas bottles, a valve house with the reserve gauges, a charger fed from the network, and a dry transfer
chamber above the collar with a locker of scrubbers and a decoy or two. Locked by Tristan on 2026-11-28.

| File | View | Lineage |
| --- | --- | --- |
| `air_depot_primary.png` | The sub docked under the arm, the tank yard behind | v3, a paint-over of the greybox camera `docked` |
| `air_depot_three_quarter.png` | Three-quarter: the bottles in their cradles, the valve house, the gantry | v2, a paint-over of `three_quarter` |
| `air_depot_approach.png` | The approach, as the sub comes in | v1, a paint-over of `approach` |
| `air_depot_valve_detail.png` | A diver at the reserve gauges and valve panel | v4, a paint-over of `diver_gauges` |

Layout: `assets/models/facilities/air_depot/program.yaml` (checked by `tools/facility_plan/site.py`, including the
docked mode); greybox renders in its `renders/blockout/`. All five paint-overs came back faithful at the first try: the
brief lists exactly what the site contains and forbids additions.
