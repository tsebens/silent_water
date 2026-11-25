# Sub frame: still interior, moving world

**Decision:** the submarine's interior never moves. The outside world is moved around it.

## How it works

- The redesigned sub's hull is generated from `assets/models/vehicles/sub_interior/program.yaml` by a parametric script (decision #395; hull arc under #396). The Onshape pipeline below is **legacy** and stays until that hull replaces it.
- The legacy geometry comes from the Onshape concept: `tools/convert_sub.py` turns `assets/media/sub/Assembly 1.gltf` into `assets/sub/sub_model.glb` (Godot axes, origin on the main cabin floor at the centreline, bow toward -Z, simplified meshes, named parts). `SubModel` gives the parts their materials and collision. The hull is about 10 m × 4 m; the pilot well is 0.6 m below the cabin floor.
- `Game/Interior` sits at the origin with an identity transform, permanently. Players, controls, interior lights, and the sub's exterior lights (the headlight) live here. Everything inside the sub is in **sub-local space**.
- `Game/World` holds everything outside the sub: terrain, creatures, objectives. Its children use **world space** as their local space.
- `SubFrame` owns the sub's pose in the world (`sub_transform`, host-authoritative, replicated). Each frame it sets `World.transform = sub_transform.affine_inverse()`. In render space the sub is always at the origin, and the world moves past it.
- Players sync `sync_position`, `sync_yaw` and `sync_pitch` in sub-local space. The sub's motion can't jitter, slide or desync the crew, because it never touches their transforms.

## Gravity and tilt

`SubFrame.gravity_in_sub()` returns world gravity expressed in the sub's frame. The deck stays physically flat (the player's `up_direction` is the sub's up), so `Player` treats the tilt itself:

- Below `Player.SLIDE_ANGLE_DEG` (30°), boots grip. A standing player doesn't move, walking uphill is slower and walking downhill is faster.
- Past 30°, the along-deck part of gravity acts and the crew slides.

## Collision layers

| Layer | Bit | Contents |
| --- | --- | --- |
| 1 | 1 | Interior hull and fixtures |
| 2 | 2 | Interactable grab volumes (raycast only) |
| 3 | 4 | Players |
| 4 | 8 | Exterior world (terrain, rocks) |

Players collide with layers 1 and 3 only, so exterior geometry moving through render space never touches the crew.

## Consequences for later systems

- **Sub physics (M2)** is a custom integrator on `sub_transform`. For collisions with terrain, cast the hull shape from the origin along the sub's velocity (rotated into render space) against layer 4. In render space the sub is always at the origin.
- **Audio (M3/M4):** world sound sources live under `World`. The listener is the local player's camera in the interior. Both share render space, so 3D audio positions are correct with no extra work.
- **Exterior particles** such as marine snow must be anchored in world space. A particle system emitting in render space would travel with the sub.
- **Floating point:** the sub's absolute world position stays small in prototype maps. Large maps may need origin shifting of `sub_transform`.

## Clients

The host writes `sub_transform` at physics rate. Clients receive it at 20 Hz and smooth toward it (`SubFrame.CLIENT_SMOOTHING`), so the world on a client lags the host by a few tens of milliseconds. A slow, heavy sub hides this.

## Bilge

`SubPhysicsModel.bilge_water_t` (tonnes) is uncapped above and floored at 0. Leaks add it, the pump removes it, and every tonne adds mass, so enough bilge water keeps the sub from surfacing even with the tanks blown. It never destroys the sub by itself. Height over the floor is `bilge_height_m(t) = t / INTERIOR_FOOTPRINT_M2` (1 t = 1 m³; footprint 20 m², tunable), so 3 t is 0.15 m and 4 t is 0.20 m. The controller replicates `bilge_water_t`; clients derive height from it. The bilge gauge reads 0..8 t and pins at full scale above that.

### Bilge water surface

`BilgeWater` (`src/sub/bilge_water.tscn`) is a child of the still `Interior`. It sits at `bilge_height_m(bilge_water_t)` above the floor, is hidden when dry, and eases toward the replicated tonnage on every peer. Its shader (`bilge_water.gdshader`) is a minimal translucent rippling surface, clipped to the hull cylinder; the ocean surface can adopt it.

## Program frame and the interior frame

The sub interior program (`assets/models/vehicles/sub_interior/program.yaml`) is written in the **program frame**: origin at the hull's centre, +X starboard, +Y up, +Z toward the stern, with the main deck at y = -0.95. The game's interior frame (everything under `Interior`, above) has its origin on the main cabin floor at the centreline. The two differ only in height:

| Interior | = Program |
| --- | --- |
| x | x |
| y | y + 0.95 (the program's `main_deck_y`, negated) |
| z | z |

So the main deck is y = 0, the sunken cockpit floor (`floor_offset_m: -0.20`) is y = -0.20, and a standing eye (1.65 m) is y = 1.65.

`plan.py` resolves the program into `layout.json` (stations, features, footprints, floors, clearances, cameras). `SubLayout` (`src/sub/sub_layout.gd`) reads it and is the **only** code that converts between the frames: `to_interior`, `to_program`, `position(id)`, `footprint(id)`, `floor_y(compartment)`, `cockpit_floor_offset()`, `clearance(key)`. Other systems ask it; none repeat the offset. After changing `program.yaml`, run `uv run --project tools/asset_pipeline python assets/models/vehicles/sub_interior/plan.py` and commit `layout.json`; `tests/unit/test_layout_in_sync.gd` fails when it is stale.
