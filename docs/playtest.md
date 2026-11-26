# Playtest guide

The prototype asks one question: **is it tense and fun to coordinate a sub when talking is dangerous?**

## Setup

1. **Crew:** 3–4 players (4 is the target). One hosts.
2. **Voice:** talk over an external voice app (Discord or similar). The game measures each player's mic separately for noise. Use push-to-talk off or voice activity in the voice app, so the game hears what the crew hears. Use **headphones**, so the game's sounds don't leak into your mic.
3. **Build:** everyone needs the same commit and Godot 4.7.2 (standard, not .NET).
4. **Network:** the prototype has no Steam lobby yet. The host's port **24550/UDP** must be reachable: same LAN, a VPN such as Tailscale or ZeroTier, or a port forward.

Host:

```bash
godot --path . -- --host --name Tristan
```

Each crew member:

```bash
godot --path . -- --join <host-address> --name <your-name>
```

You can also launch with no arguments and use the dev connect menu.

To try it alone with several windows on one machine:

```bash
tools/launch.sh 4
```

## The dive

The **orders** are on the board on the aft bulkhead:

1. Scan Raindrop sensor array **S-7** on **shelf 2** (east wall, ~140 m). It has a red beacon and an acoustic **pinger** the sonar operator can find.
2. **Surface** for recovery.

You start floating at the surface with empty tanks. Flood to go down. The canyon has a close first shelf (~60 m), the array's shelf (~140 m), and the floor (~230 m), where there is a loud vent. Something big lives down there. It's blind and hunts by sound.

A dive ends when you surface after the scan (success) or when it reaches you (loss). Either way, the dive resets after a few seconds.

## Stations

| Station | Where | What you do |
| --- | --- | --- |
| **Helm** | Bow, in the pilot well under the glass dome | Press **E** at the seat to take the helm (E again to stand). **W/S** throttle (it stays where you leave it), **A/D** rudder, **R/F** dive planes (F noses down). **A/D** turns even when stopped (side thrusters, which make some noise); the rudder adds more turn once you're moving. The dive planes only work with water moving over them. Gauges either side: depth, pitch, noise, heading, speed. A centre pod below the dome adds buoyancy (net vertical acceleration, sinking left), vertical speed (down left) and throttle (effective engine output, astern left; reads 0 inside the lever's dead zone). The **pilot's map** hologram in front of you is heading-up and centred on the sub (about 115 m around), with terrain, the objective, pins and sonar contacts. **Cabin lights** lever by your left hand dims the cabin so you can see out. You can't work other stations while seated, so call your orders out. |
| **Ballast** | Port wall, forward cabin, by the bulkhead | **FLOOD** valve (quiet) makes the sub heavier. **BLOW** valve (very loud, uses limited HP air) makes it lighter. Turn the handwheels by circling the mouse. Gauges: tank, HP air. The pilot can also run these from the helm with Numpad 8/2 or Page Up/Page Down. |
| **Sonar** | Starboard desk, forward cabin, against the bulkhead | Press **E** at the seat to sit; that puts the headset on. Circle the mouse on the **hydrophone wheel** to turn the listening bearing; the dial on the bulkhead shows where you're listening, and both maps show it as a yellow fan. **Scroll** to set an estimated range, **M** to mark a contact at that bearing and range on the shared chart. Only you hear the hydrophone, and you must say what you hear out loud. |
| **Map table** | Midships, port bay | The generated `map_table` station: a D-shaped top with a low terrain relief, a curved panel of light behind it and two work lamps. Walk up and use the console: roll the **trackball** to pan, push the **lever** up or down to zoom (it springs back), flip the **toggle** to follow the sub (the lamp lights while following). Press **E** to lean over the hologram (cursor appears). **WASD** pan, **wheel** zoom, **Q / R** (or hold the **middle button** and drag) rotate the chart, **F** follow the sub, **1-4** pin type (waypoint, danger, last seen: apex, note), **click** place a pin on the terrain, **right-click** remove one, **E** step back. The operator stands: there is no seat. The sub arrow shows the heading. Pins, sonar contacts and the yellow sonar fan show here and on the pilot's map. |
| **Scanner** | Starboard wall, aft engineering (beside the bilge well) | **Scanner** switch: within ~30 m of the array, nearly stopped, it fills the SCAN gauge in ~25 s. It's **loud** the whole time it's on. |
| **Engineering** | Aft compartment, through the bulkhead door | Engine gauge. The pilot sets speed; engineering's future job is engine upkeep. Life support is the rack of cylinders. |
| **Bilge** | Aft compartment, port side | **Pump** switch: removes leak water, but it's loud. |

**Leaks** hiss and spray. Find them by ear, then click and hold **steady** for 2 s to patch. A shaky patch doesn't last.

**Noise gauges** (one at every station): the red needle is the sub, the blue needle is the ocean. Red under blue means you're hidden.

## Controls

| Input | Action |
| --- | --- |
| Mouse | Look. The dot at screen centre lights up over anything usable and says what it is and how to use it. |
| Click (hold) on a control | Grab it; move the mouse to work it. The view holds still while the button is down. Ease it for quiet, slam it for a clank. |
| E | Take or leave a station: the helm, the sonar headset |
| WASD | Walk; at the helm, W/S throttle and A/D rudder |
| R / F | At the helm: dive planes (R rises, F dives) |
| Numpad 8 / 2 (or Page Up / Page Down) | At the helm: blow / flood while held |
| Space | Hop (clears steps and seat edges). Landing makes a thud, louder than a footstep |
| Shift | Sneak (quieter footsteps) |
| Esc | Release the mouse and let go of everything |

## What makes noise

Roughly loudest first:

- blowing ballast
- slamming controls
- hull strikes
- shouting
- the scanner
- the engine at speed
- the bilge pump
- normal talking and walking
- a leak
- flooding
- sneaking

Whispering and a still sub hide under the ocean. Vents mask you if you're close to them. They also deafen the sonar.

## The monster's tells

Every step up the ladder can be heard or felt:

| What you notice | What it means |
| --- | --- |
| Long, distant **moans** now and then | Unaware |
| **Moans more often**, moving around more | Patrolling: it heard something a while ago |
| **Grunts** | Curious: it's drifting toward a noise |
| Rhythmic **pulse trains** | Hunting: it's searching where it last heard you |
| A **roar** | Committed: it's charging where it last heard you. Go silent and move. |
| Low **rumble** you feel, then **shaking, flickering lights, creaking** | It's close |

Arousal fades about 30 seconds after you go quiet. Patrolling lasts a minute or two after that.

## Dev tools

### Terrain lab

A developer scene for shaping dive sites without hosting a session. Open it with the **Terrain lab** button on the dev connect menu, or launch straight into it:

```bash
godot --path . -- --terrain-lab
```

It is not part of a session: there is no sub, crew or network, and nothing in a running dive leads to it. **Back** returns to the dev menu.

The scene is a `CanyonSite` generated from a `SiteSpec`, the ocean surface, and the day and night light presets for context. It calls the same generator and `height_at` as the game, so what you see is what a session builds from the same spec and seed.

- **Camera:** hold the **right mouse button** to look; while held, **W/A/S/D** fly, **E/Q** rise and sink, **Shift** is fast, and the **wheel** changes speed. Without the button, keys go to the panel.
- **Panel (left):** a control for every `SiteSpec` field (seed, centreline, rim and floor, wall shape, width and depth curves, closed ends, shelves, constraints) and every exported `CanyonSite` tunable (profile, strata, detail, ambient occlusion). New exports appear automatically. Lists (shelves, constraints) have **Add** and **Remove**; the centreline and curves are typed as `x,z; x,z` points (curves are `t,value`, `t` from 0 at the south end to 1 at the north; empty means none).
- **Seed** sits at the top with **Random**. **Regenerate** rebuilds the site. With **Auto** on, an edit regenerates after a short pause, as long as the last build took under 1.5 s; slower builds wait for the button.
- **Readout:** how long the last build took, and any conflicts `SiteSpec.validate()` finds between constraints.
- **Day / night** switches the light preset.
- **Constraint overlay:** every constraint is drawn as a wireframe over the terrain: a `FlatPad` as a gold ring (inner ring is the pad, faint outer ring its falloff, plus a post at its height), a `Corridor` as a cyan outline with its centre ramp, a `ClearColumn` as a pink cylinder. It follows edits at once, without waiting for a regenerate. Constraints are added, removed and edited through the list in the panel; the same operations are `LabPanel.add_constraint`, `move_constraint` and `remove_constraint`.
- **Spec files:** the two path rows under the buttons. **Save spec** writes the edited `SiteSpec` (constraints included) as `.tres`; **Load spec** replaces the edited spec with one. The default path is `user://lab_spec.tres`.
- **Heightmap:** **Export heightmap** samples the generated ground over the generator's grid (2 m cells) and writes a PNG plus a `.json` sidecar beside it. Each pixel holds a 16-bit height code, high byte in red and low byte in green (Godot has no 16-bit greyscale), row 0 at the minimum z. The sidecar gives the extent (`x_min`, `z_min`, `x_max`, `z_max`), `cell`, the grid size, and the vertical range (`min_y`, `max_y`, `vertical_scale` = range / 65535). `y = min_y + code / 65535 * (max_y - min_y)`. **Import** reads a PNG and sidecar back and reports its size and range; heights reproduce within one `vertical_scale` step (`SiteIO.import_heightmap`).
- **Erosion:** an **Erosion** section of the panel holds every `ErosionParams` field. `enabled` turns grid erosion on (it is off by default, so the ground stays analytic); `cell_size` is the grid resolution (smaller is finer and slower). Three passes run in order, each with its own toggle and parameters: **Droplets** (seeded hydraulic erosion: droplets pick up, carry and deposit sediment as they run downhill), **Thermal** (material steeper than the talus angle slumps downhill) and **Deposition** (flat ground settles toward its neighbours' mean). Cells under a constraint are never changed. The readout lists the milliseconds each pass took and the total.
- **Before / after:** the **Eroded** checkbox next to Auto switches between the eroded ground and the analytic ground before erosion (the site is rebuilt either way). **Export heightmap** always writes the eroded grid when erosion is on, even from the before view, so the exported file is the frozen result. Whether a game session bakes the grid or loads one is not settled (Decision #207).

The lab starts from the canyon preset (`src/site/presets/canyon.tres`) and edits a copy; it never writes the preset back.

## Debug keys (playtests only)

| Key | What it does |
| --- | --- |
| F1 | Developer overlay: console (engine output and game events, including the host's on clients), 3D minimap (sub green, apex red, array yellow), and live sub, noise, apex and dive stats. Launch with `-- --dev-overlay` to start with it on. |
| F5 | Single-player mode: the helm also runs the ballast (Numpad 8 or Page Up to blow, Numpad 2 or Page Down to flood, while held). Turns on automatically when you host alone in a development build (start with `-- --crew` to skip that); F5 toggles it. |
| F4 | Switch the apex off or on for everyone (the host decides). While it's off, it's gone: no body, no sound, no hearing, no contact. Start the host with `-- --no-apex` to dive without it from the start. |
| F6 | Switch spontaneous leaks off or on for everyone (the host decides). Hull-strike leaks still open. Start the host with `-- --no-leaks` to dive without them. |
| F7 | Flip the surface light preset between day (default) and night. Start with `-- --night` for night. |
| F3 | Simulate normal speech on your mic |
| Shift+F3 | Simulate a shout |

## Surfacing light

Ascend slowly through the last 40 m. By day the water should visibly brighten well before the depth gauge reads near zero; by night (F7) the same cue should be there but subtle. Report whether either is too strong, too weak or too late. Presets live in `src/world/presets/`.

## During and after

- **Don't coach the crew** about talking quietly. Watch whether they start on their own.
- The host's game writes a **session log** (its path is printed at the start; it lives under the Godot user data folder, `logs/session_*.txt`). For each change in the monster's state, the log records how loudly it heard the sub and the **loudest things aboard at that moment**. Use it to answer "what gave us away?"

### Success criteria

1. Crews start whispering, calling out tersely and going silent without being told.
2. Players can tell where the monster is on the ladder from sound alone.
3. After a loss, the crew can say what gave them away. Check their answer against the log.

### Report

File a **Playtest feedback** issue (template in `.github/ISSUE_TEMPLATE`) and attach the session log. Put tuning numbers you'd change in the issue: most live in `SuspicionTuning`, `docs/noise.md` and `docs/apex_and_sonar.md`.
