# terrain_sketch

Numpy prototype of the macro terrain generator for large, procedurally generated dive sites (#952). It is the
concept art for the terrain: agree the look and the rules here on hillshade renders, then port the agreed
algorithms to GDScript under `src/site/` beside `CanyonSite`, which stays as it is.

```
uv run sketch render --seeds 3 7 11 --out <dir>   # one hillshade per seed, stations placed, log and depth histogram
uv run sketch stats --seeds 1..50                  # how many seeds pass the viability gate, and why the rest fail
```

## Stages

1. **Landforms** (`landforms.py`, about 0.4 s). A map preset fixes the size (about 1.7 x 2.75 km, the golden
   ratio, 10 m macro cells) and the depth range. The base field is a warped noise field pushed into three flats
   (deep plain, mid terrace, shallow shelf) drawn from the station depth bands, with the step positions set by
   area share so every level has ground; fault scarps shift blocks up or down a level before the staircase.
   Then chasms along smooth splines with tributaries, collapse pits and ridged seamounts are pressed in with
   smooth min/max.
2. **Macro erosion** (`erosion.py`, about 0.2 s). D8 flow routing and stream-power incision on slopes, talus
   slump, sediment fans where fed channels leave steep ground, and mudflat fill on gentle low ground.
3. **Viability gate and placement** (`stations.py`, about 0.03 s). Each station class has a depth band, a
   footprint and the most relief a levelled pad can absorb. A map is viable when every class has ground and a
   farthest-point placement spreads the stations across the map with no outlier.

The gate run after stage 1 agrees with the gate after stage 2 on 43 of 50 seeds, so it works as the early
filter; final placement runs again after the slow stages.

Station classes and depth bands in `stations.py` are placeholders for the real station list.
