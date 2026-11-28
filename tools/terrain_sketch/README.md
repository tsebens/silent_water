# terrain_sketch

Numpy prototype of the macro terrain generator for large, procedurally generated dive sites (#952). It is the
concept art for the terrain: agree the look and the rules here on hillshade renders, then port the agreed
algorithms to GDScript under `src/site/` beside `CanyonSite`, which stays as it is.

```
uv run sketch render --seeds 3 7 11 --out <dir>   # one hillshade per seed, stations placed, log and depth histogram
uv run sketch stats --seeds 1..50                  # how many seeds pass the viability gate, and why the rest fail
uv run sketch detail --seeds 1 5 --out <dir>       # the detail pass on viable seeds: overview, crops, pad cut and fill
```

## Stages

1. **Landforms** (`landforms.py`, about 0.6 s). A map preset fixes the size (about 1.7 x 2.75 km, the golden
   ratio, 10 m macro cells) and the depth range. The base field is a warped noise field pushed into three flats
   (deep plain, mid terrace, shallow shelf) drawn from the station depth bands, with the step positions set by
   area share so every level has ground; the rises between levels wander and vary from cliff to ramp, and each
   level carries its own swales and low rises. Fault scarps, warped and broken, shift blocks up or down a level
   before the staircase. Then chasms (warped edges, swelling and pinching, one cliff wall and one ramp, uneven
   floors) with tributaries, lobed collapse pits with ledges, and elongated seamounts with summit plateaus or
   craters are pressed in with smooth min/max.
2. **Macro erosion** (`erosion.py`, about 1 s). In order: stream-power incision where there is real upstream
   drainage; talus slump (8-neighbour); transport-limited sediment routing along the flow graph (flow picks up
   material below capacity and drops it above, never on cliffs, deposits spread over neighbours); fans at
   channel mouths where a fed channel leaves steep ground (apex at the mouth, opening downslope, sized by
   drainage area, with distributary ribs); ponding, which fills closed basins (pit floors, chasm pools) part
   way with flat sediment so they become mudflats with their walls still standing; then the mudflat fill on
   gentle low ground. The mudflat weight is computed once from smoothed ground: a per-cell threshold
   recomputed each pass broke every cliff foot into teeth. Erosion also returns a sediment-thickness grid,
   drawn as a silt tint, and later the basis for choosing sediment or rock materials.
3. **Viability gate and placement** (`stations.py`, about 0.03 s). Each station class has a depth band, a
   footprint and the most relief a levelled pad can absorb. A map is viable when every class has ground and a
   placement spreads the stations across the map with no outlier. Placement rewards spacing up to a cap and
   then prefers the interior, and keeps a 220 m margin, so stations do not all go to the edges.

4. **Detail** (`detail.py`, about 5 s, only for a map that passed the gate). Upsample to 2 m cells (about
   1.2 million), classify ground as rock (steep, little sediment) or sediment, then add detail by material:
   ridged crags, a blocky texture and warped strata ledges of varying thickness on rock; scree lumps below
   cliffs; rugosity from 70 m down to about 6 m everywhere; sand waves across a seeded current on gentle soft
   ground. A fine slump, a boulder scatter (below cliffs and on rock), then each station's pad is levelled to
   the median ground in its footprint and blended out, with the cut and fill reported per pad. The crops use a
   local-relief render (the surface smoothed over about 60 m is subtracted before shading), because plain
   hillshade at this scale shows only the big slopes.

The gate run after stage 1 agrees with the gate after stage 2 on 25 of 30 seeds (round 3), so it works as
the early filter; final placement runs again after the slow stages. 26 of 30 seeds are viable.

Station classes and depth bands in `stations.py` are placeholders for the real station list.

## Port plan: chunking (decided)

At the game's fog density (0.018 per metre) terrain is 99% hidden by about 260 m, so a camera never sees more
than about 5% of a map. Decided (Tristan, 2026-11-28): **fixed tiles with distance culling**. The 2 m grid is
cut into square tiles (for example 64 x 64 cells, 128 m), one mesh each, whose visibility range ends just past
the fog distance. The detail pass is local, so each tile's detail is generated lazily as the sub approaches,
with a small overlap so slump matches across seams; collision is per tile near the sub and the apex; the
holographic maps keep the 10 m macro grid.

Kept for reference:
- **GPU clipmap:** nested camera-centred rings with heights from a texture in the vertex shader. The upgrade
  path if clearer water extends sight lines.
- **Terrain3D addon:** clipmaps, collision, texturing and editor tools, at the cost of a native dependency
  pinned to Godot versions and its own region and material systems.

Still open: tile size, and lazy detail versus generating everything at load behind a progress screen.

## When detail runs (decided), and what a tile costs in GDScript

Decided (Tristan, 2026-11-28, #976): **background fill, nearest first.** Macro, gate and placement at load;
the per-tile detail pass then runs on worker threads from the sub's start outward; the dive starts once the
start area is ready; queries on unfinished tiles use the 10 m macro heights.

`bench/tile_bench.gd` times one 64 x 64 tile (2 m cells, 4-cell margin) in GDScript. It sits behind a
`.gdignore`; to run it, copy it into the git-ignored `.asset_work/scratch/` and run
`godot --headless --path . -s res://.asset_work/scratch/tile_bench.gd`. Results in this container (headless
editor binary, so an exported game should be no slower):

| Step | ms per tile |
| --- | --- |
| Noise, 7 layers, sampled per cell | 4.5 |
| Noise, 7 layers, filled by the engine in batches | 3.5 |
| Combine (materials, crags, strata, rugosity, ripples) | 3.1 |
| Slump, three 8-neighbour passes | 10.0 |
| Mesh build | 1.7 |
| Collision shape | 0.3 |
| **Total** | **about 19** |

The whole map is 286 tiles: about 5 s on one thread. Batched noise saves only about 1 ms and the engine's
batch output is 8-bit, so per-cell sampling (full precision) is the better choice. The slump is the costliest
step. Not yet timed: the macro stage in GDScript (flow routing and sediment routing over about 47,000 cells,
ten passes), which has the heaviest loops of the pipeline.
