# Research hub: concept art

## Locked concept (2026-11-28)

The research station (#853), locked by Tristan as "a great starting point":

| File | View | Lineage |
| --- | --- | --- |
| `research_station_primary.png` | The approach from the chasm: the cantilevered tier on its struts, the docking arm over the drop with the sub mated to its collar | v37, a refine of v31, a paint-over of the greybox camera `chasm_approach` |
| `research_station_overview.png` | The whole site: main block, maintenance, docking arm, tunnels, power building, mast | v39, a refine of v36, a paint-over of the greybox camera `overview` |

They were painted over the greybox built from the floorplan (`assets/models/facilities/research_station/`): the
layout is `program.yaml`, the greybox renders are in its `renders/blockout/`, and each painted view keeps its greybox
camera. So the art matches the plan, and a build can be rendered from the same cameras and compared. The exterior
is far bigger than the rooms on purpose: the presence comes from the concrete (thick walls, plinth, the tier,
buttress fins), not the room count.

## Exploration

Concept art for Raindrop's regional research and operations hub, generated in Asset Studio (`research_hub`,
architecture class, scene presentation). The asset's brief in `../asset.yaml` carries the style in words; every
variant's prompt, model and cost is in its lineage. The images themselves stay in the git-ignored
`.asset_work/research_hub/concept/` until a design is chosen for the station brief.

## Style board (`style_board.jpg`)

The house style for Raindrop's infrastructure, chosen by Tristan from rounds 1 and 2.

| Variant | Why it is on the board |
| --- | --- |
| v8 (after the Barbican) | The closest to the intended feel: splayed X-piers, cantilevered tiers, a lit hangar mouth |
| v2 | Buttress fins along the walls; a hangar big enough for several subs |
| v4 | Long cantilevers with deep ribbed undersides on angled struts |
| v9 (after the National Theatre) | Stacked terraces and blocks sitting on the edge of the drop |
| v6 | A tiered tower and steel A-frames. **At the limit**: its tower comes close to the layering v20 shows |
| v20 | **What not to do.** Many identical floors stacked like an office block, each with a continuous band of windows. The layering and glazing break the solid, fortified mass the style depends on |

Lessons from generating it:

- A grid of images used as one reference makes the image model copy the grid or a single panel (v12–v14). Use the
  brief's words, or one image at a time.
- Several variants drew a water surface at the base (v5, v6, v11, v17, v20). The brief now says the hub is fully
  submerged.
