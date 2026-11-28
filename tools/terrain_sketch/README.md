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
3. **Viability gate and placement** (`stations.py`, about 0.03 s). The terrain knows one kind of station: an
   id, a depth band, a footprint radius and the most relief its levelled pad can absorb. The game passes a list
   at runtime, one entry per station (`stations_example.json` is a placeholder list); what each station is,
   is not the terrain's concern. The base field's flats are derived from that list by interval stabbing: the
   fewest depths such that every station's band contains one, each flat placed in the middle of the overlap
   of the bands it serves. A map is viable when every station has ground and placement spreads the stations
   across the map with no outlier. Placement rewards spacing up to a cap and then prefers the interior, and
   keeps a 220 m margin, so stations do not all go to the edges.
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

## The macro stage in GDScript

`bench/macro_bench.gd` times the heavy parts of the macro stage on the same 171 x 276 grid (run it the same
way as the tile benchmark). Results in the cloud container:

| Part | ms |
| --- | --- |
| Base field (7 noise fields) | 69 |
| Distance to 8 curves of 48 segments, culled to 400 m | 239 |
| Incision, 6 passes with flow routing (one routing about 67 ms) | 410 |
| Slump, 4 passes | 104 |
| Sediment routing, 10 passes with flow routing | 880 |
| Priority-flood basin fill (binary heap) | 212 |
| Gate relief windows, 4 footprint sizes | 411 |
| **Total** | **about 2.3 s** |

Flow routing sorts the grid natively by packing height and cell index into one 64-bit key, which avoids a
script comparator. Not timed: fans, ponds and the mudflat smoothing. The mudflat step repeats wide blurs
eighteen times; done naively in GDScript that would cost more than everything above, so the port uses
running-sum box blurs, which cost the same at any width. The gate windows can use the same running trick.
A rejected seed costs only the stages before the early gate.
