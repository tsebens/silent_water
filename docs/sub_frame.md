# Sub frame: still interior, moving world

**Decision:** the submarine's interior never moves. The outside world is moved around it.

## How it works

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
