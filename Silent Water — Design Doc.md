# Silent Water — Design Doc

Nov 18, 2026 · @Tristan

## Overview

Silent Water is a first-person co-op submarine stealth game for a crew of four, with three also viable. The crew runs a small, old, well-built sub through deep-ocean dive sites while something enormous listens. Talking is how the crew survives, and talking is what gets them found.

**Inspirations:** Lethal Company (communication is the game; short runs grouped together), Darkest Dungeon (nested loops where every decision costs at several levels), Helldivers 2 (objective chains, difficulty-based scaling, in-world menus), Iron Lung (no HUD, physical instruments), and Barotrauma (the closest existing game: a co-op sub with stations and sonar).

### Design pillars

1. **Communication is the danger.** Control is split across stations so no one can run the sub alone. Coordinating means talking, and talking makes noise.
2. **No fighting back.** The crew has no offensive capability against anything that matters. They survive by hiding, running and outthinking.
3. **Physical over abstract.** Information comes from in-world instruments, and controls are worked by hand, wherever practical.
4. **Fair dread.** Death can be sudden but never unannounced. Every threat telegraphs its escalation.
5. **Decisions cost at every level.** A choice inside a dive affects the expedition, and expedition choices shape every dive.
6. **Multiplayer only.** No single-player mode. The game lives in the crew's interactions.

## Setting and tone

Something opened on the ocean floor, and it broke the world. Humanity survives, diminished, and holds the line with an aging network of deep-sea monitoring and containment infrastructure. When the network goes untended, things get worse, so crews keep going down.

- **Raindrop** (working name) is the organization that built and runs the network. The name comes from the Dinotopia proverb "one raindrop raises the sea."
- **Competent builders, overwhelming force.** Everything Raindrop built is overbuilt, labeled, redundant and maintained. It fails from age, pressure and attack, never from sloppiness. Damage reads as a siege: corrosion, crushing, things torn open.
- **Humanity is on the back foot.** Resources are thin and the network is overextended. Technology is industrial, mechanical and robust, closer to Zion in the Matrix films than to sleek sci-fi.
- **Mostly unmanned.** Sites are sensor arrays, cable runs, automated labs and drone bays. The loneliness should feel close to deep space.
- **The rift is never fully explained.** It is the source of the creatures and the reason they vary from site to site.
- **Infrastructure is an ally.** Restored stations can help the crew with deterrent pulses, places to top up air, or beacons. Fixing things gives the crew power.
- **Tone:** a measured thriller rather than gore horror, dark and scary at roughly Lethal Company's level. Cosmic, Lovecraftian, New England maritime. References: the film *Underwater* (2020), the SCP Foundation, and the game *Control*.

## Game structure

Play is three nested loops: a dive of about 30 minutes, an expedition of 2–5 dives (about 1.5–2.5 hours), and the hub between expeditions. A fourth, outer loop is possible but deferred until dives play well.

&#91;embedded content: Nested loops · hub, expedition, dive\]

Hull damage and supplies carry from dive to dive within an expedition; repairs and restocking happen back at the hub.

### Dive

One descent, the objectives, and an ascent to the expedition ship. A dive ends when the sub surfaces or is lost.

### Expedition

- The crew picks a region, each with a difficulty, and loads the expedition ship's limited cargo.
- The ship travels between dive sites, each with its own difficulty. Before each dive, the crew loads the sub's smaller cargo from the ship.
- Hull damage, supplies and cargo carry over between dives. Whatever is left at the end comes home.
- The expedition saves between dives, so a crew can stop and resume later, even with a different player.
- **Routing is an open question.** The lean is Lethal Company–style free routing, where your current site changes the travel cost to the next, over a locked node map. Decide once the dive loop is proven.

### Losing the sub

- **Default: the sub is recovered.** It comes back more damaged than when it was lost. The crew loses that dive and everything aboard. If the sub is too wrecked to dive, the expedition ends and the ship's cargo comes home.
- **Fallback to test if that fails:** a fixed pool of three subs per expedition, like lives.

### Hub and progression

- The hub is an island outpost, one of many rather than the last. It is a physical place the crew walks around: a dockyard, a supply depot, and a map table for choosing expeditions.
- Earnings go to repairs, then consumables, then upgrades.
- **No hard locks.** Every region is open from the start; gear decides what is reachable. Hard limits are the hull's pressure rating and the ship's range. Soft limits are air, fuel and engine efficiency.
- Sub upgrades include engines, air tanks, ballast, lights, sonar, and mounts like a drone clamp or capture net. Ship upgrades cover cargo, range and speed.
- **Every upgrade costs noise, space, power or weight.** Limited mounting points force a loadout choice. Gear can make the sub quieter, but nothing makes noise stop mattering.
- **Challenge scales with depth.** Better gear reaches deeper water, and deeper water is harder, which avoids the late-game ease of games like Dredge. Distinct sub types with trade-offs are a later goal.

## The sub and crew

The target crew is four. Three should be able to run the same sub at a lower difficulty; two is not a design target. Difficulty scales the world, never the sub, following Helldivers 2 rather than Sea of Thieves.

### Stations

There are more jobs than people, so the crew keeps moving between stations, and moving makes noise. Start with one all-rounder sub.

| Load | Station | What it involves |
| --- | --- | --- |
| Constant | Pilot | Steering, diving planes and engine speed (throttle); rarely leaves the seat |
| Dominant | Sonar | Hands-on listening and pinging; the only person on the hydrophone |
| Midway | Engineering | Engine upkeep and power; no longer sets speed (decided in M7) |
| Rounds | Ballast | Valves that flood and blow the tanks for big depth changes |
| Rounds | Life support | Scrubber canisters, fans, O2 |
| Rounds | Bilge and leaks | Pumps and patching |
| Rounds | Countermeasures | Decoys and noisemakers; replaces the original concept's weapons station |

The original concept also had a charts station. It became the **map table** (M7): a holographic terrain display built into the port wall of midships, with a standing operator who moves the camera and standing observers who drop pins. Everyone at the table stands; whoever steps up leans over it, about 0.25 m below the standing eye and 0.15 m further over the table, the same for everyone, and the hologram is tuned for that leaning eye height. Only the operator's console and keys drive the camera; observers step up at two points either side of the operator and place and remove pins (concept in `assets/models/map_table/concept/`). The hologram is a low relief of contour lines lying on the tabletop, with a curved panel of light along the back edge as a backdrop (round 6, #380). The operator pans with a trackball, zooms with a lever and follows the sub with a toggle; rotation is on mouse and keyboard, and the console's knob is decoration. Countermeasures stands against the starboard wall just aft of the sonar station, across the aisle from the table, so its operator can watch their decoys on the hologram. The pilot has a smaller heading-up hologram of the same shared chart, in the same display model.

### Controls

- **Physical by default:** valves, levers, switches and sliders worked with the mouse.
- **Keys only for continuous fine control** that a mouse would make clunky. That covers the pilot's steering, diving planes and throttle.
- **Discrete, occasional actions stay physical**, even ones the pilot needs, like ballast. Big moves take a second person. (Engine speed moved to the pilot's throttle in M7: an order telegraph made driving feel sluggish. Side thrusters let the sub turn in place, at a noise cost.)
- **Speed of movement sets noise.** Easing a lever is quiet; slamming it clanks.
- **No HUD by default.** In-world screens the camera zooms into, like Helldivers 2's map table, are fine where a physical version is impractical. Prefer handling cargo physically over grid inventories.

### Weight and buoyancy

- Everything has weight: the sub, its loadout, cargo, salvage, crew and rescued survivors.
- Weight limits buoyancy and climb rate. A failed ballast tank can leave an overloaded sub unable to rise.
- Ways out: ditch salvage, or release emergency drop weights once, as real deep-sea subs like Alvin can.
- Optional: crew position shifts the sub's trim, and the pilot has to correct.

### Damage and repair

- Leaks hiss and spray, and are found by ear.
- **Field patch:** free but uses a quick spatial mini-game; its quality sets how long it holds.
- **Instant patch:** a strong consumable that takes cargo space.
- **Welded plate:** a permanent fix, but heavy cargo, and welding is loud, so it has to be timed.
- Hull damage lowers the sub's safe depth, and breakdowns grow more frequent with pressure.

## Noise, stealth and sensing

Noise is the core system, and every other system feeds into it.

### Noise model

- **Sources:** voices, footsteps, engine speed, pumps, fans, controls moved quickly, repairs (welding is loudest), active sonar, and accidents like dropped tools or hull strikes.
- **One number for the sub.** The sub is tiny next to the monster, so every source inside it sums to a single noise level at the sub's position. It falls off with distance and is blocked by terrain.
- **Sum intensity, not decibels.** Sources add as acoustic intensity (proportional to sound pressure squared). Decibels and raw pascals don't add directly. Convert the total back to a level for gauges and creatures.
- Creatures build suspicion from what they hear, which drives the escalation ladder (see Threats).
- **The mix tells the truth.** What the crew hears inside the sub matches what creatures hear outside.
- Optional: regular, rhythmic machine sounds are easier to pick out than irregular natural ones, which is how real passive sonar finds machinery.

### Noise gauge

Two needles: one for the sub's noise, one for the ocean's background noise. When the sub's needle is below the ocean's, the sub is masked. Every station gets a repeater gauge; there is no on-screen meter.

### Hiding

- **Masking:** vents, currents, whale calls and rockslides, natural or triggered. Noise works both ways: it hides you and blinds your sonar.
- **Bottom and walls:** hugging the seafloor or a canyon wall hides the sub from sonar; open water exposes it.
- **Thermocline (candidate):** temperature layers bend sound, so a sub can hide below one. It can act as a quiet boundary between depth zones.
- **Silent running:** systems shut down in stages. The scrubber fans are among the last to go; without them, CO2 builds up, so silence has a clock.

### Sonar

This is the highest-risk system. Prototype several versions.

- **Terrain is always known** from the expedition ship's pre-dive survey and shown at the charts station or pin-table. Sonar adds what moves: creatures, vents and objectives.
- **Passive (default)** is a listening job. The operator hears directional audio in their headphones and turns the hydrophone to locate sounds. It is vague and silent, and only the operator hears it.
- **Pointing the hydrophone:** a desk trackball on the sonar console, rolled sideways to swing the bearing (decided in #349; the earlier handwheel felt clunky against the modern sub). The handwheel assets stay in the repo.
- **Bearing display:** the sonar station's main bezel shows a non-interactive heading-up hologram of the chart with a cone on the current hydrophone bearing and fading blobs where the operator has marked contacts. It is a memory aid for the operator, not a sonar picture.
- **Active** pings paint a 3D cloud of points that fades over a few seconds, similar to Scanner Sombre. It is clear but loud, and gives the sub away.
- **Wide or narrow:** a wide ping is blurry and announces you everywhere; a narrow beam is sharper and quieter but shows only a slice.
- **Display options:** a phosphor point cloud, or a mechanical pin-table that rises into the shape of the terrain.

### Lights

- White light shows more but draws visual hunters.
- Red light shows less but is invisible to most deep-sea animals. That holds in the real ocean: most deep-sea animals see only blue-green, which is why research cameras use dim red light ([NOAA Ocean Explorer](https://oceanexplorer.noaa.gov/?p=5896)).
- A twist for later: a creature that sees red, like the real stoplight loosejaw ([WHOI](https://www.whoi.edu/?p=606840)).

## Threats

Keep the roster small: a few carefully designed creatures, each needing a different response. A crowded ocean kills the tension.

### Tiers

| Tier | Example | Dangerous to | Response |
| --- | --- | --- | --- |
| Apex | The big monster | Everything | Hide or run; contact means the sub is lost |
| Sub-threat | Smaller monsters | The sub (survives a few hits); fatal to divers | Dodge, distract, hide |
| Mid | A squid about 10 ft long | Divers | Survivable if warned and equipped; drive it off or escape |
| Nuisance | Cat-sized isopods, small squid | Divers | Shoo off with a knife, spear or light |

Nothing that matters can be killed. Diver tools are defensive.

### The apex monster

- Huge, blind, and hunts by sound; the original concept describes something like a coelacanth. It dwarfs the sub.
- Contact means the sub is lost. Near misses still send pressure waves that start leaks and knock things loose.
- It is felt before it is heard: low rumble, rattling fixtures, the hull flexing as it passes.

### Escalation ladder

Each step must be audible or felt, so death is never unannounced.

1. **Unaware:** distant calls, faint sonar traces.
2. **Curious:** drifts toward noise it heard.
3. **Hunting:** searches where it last heard the sub.
4. **Committed:** charges; this is the last window to break contact.
5. **Contact:** the sub is lost.

**Suspicion decays in tiers, much faster than a real predator's would.** The aim is a monster that never feels like a constant existential threat.

- **Aroused (Hunting, Committed)** is transient. It drops back about 30 seconds after the last conclusive signal.
- **Heightened patrol** sits between Unaware and Curious. The monster moves faster around the map, not necessarily toward the sub, and takes about one to two minutes to settle.
- Decay is non-linear: fast from aroused down to patrol, slow from patrol down to calm.

### Senses

Draw on real deep-sea biology. Hunters can track sound (the apex), light, vibration through a lateral-line sense, or active echolocation. Against echolocators, the counter is to sit on the bottom or hide in clutter, under a thermocline, or near a masking source. The rift explains the variety: one site might hold a single apex, another a pack of smaller hunters.

### Knowing the enemy

- **Briefing:** the map table lists likely threats from Raindrop's sensors, without certainty.
- **Field guide:** photographing or recording a creature adds its senses and behavior to a shared guide. Knowledge is a form of progression.
- **Tells during the dive:** each creature has a distinct sound and sonar signature that a skilled ear learns to recognize.

### Inside facilities

Use marine creatures in flooded stations and amphibious ones in dry stations. The station itself, with flooding, failing pressure and dead systems, is the main hazard. Infected human crew were considered but are not favored.

## Dives and objectives

### Maps

- **Vertical, deeper than wide:** canyons or shafts with shelves at tiers of depth.
- The first shelf is close, so dives start fast. Deeper shelves bring more pressure, breakdowns, danger and reward.
- The deeper the crew works, the longer and riskier the climb back out.
- Descent and ascent are played, never cutscenes. Open water exposes the sub; walls and the bottom give cover. The ascent is where desperate escapes happen.
- The dive ends when the sub surfaces and the ship recovers it.

### Objective types

| Where | Examples |
| --- | --- |
| From the sub | Photos, scans, sensor readings, finding a wreck, placing a sensor or drone, tracking or capturing a creature |
| Open water (diver) | Repairing cables, pipes and sensor arrays; retrieving an object; freeing a fouled propeller; fixing hull damage from outside; attaching a lift line |
| Inside a facility | Docking, then restoring power, pumping out flooding, pulling a data spool, replacing parts, or rescuing a crew |

### Structure

- A **main objective of 1–3 steps** plus optional side objectives, as in Helldivers 2.
- Chains combine places: find and fix a power cable, then dock, then pull the data.
- **The final step is loud or bright.** Pumps start, generators kick on, lights flood out, winches haul. Each dive builds to a moment the crew has to plan around.
- Side objectives can serve the main one. Restore a deterrent buoy first, and it covers you for the rest.
- **Gear decides what's possible.** A dive can list more objectives than a loadout can complete (a capture net, a drone clamp). The game warns but never blocks, and rewards each completed objective.
- Rescued survivors and salvage add weight, so bringing things back competes with getting back.

### Diving outside the sub

- The diver talks only over the suit radio, is the most exposed crew member, and depends on the sonar operator for warnings.
- Radio signal degrades with distance and walls, worst inside facilities.
- Emergencies can force a dive, not just objectives.

## Audio direction

There is no music. Ambient sound is the backbone of the game, and its absence makes the ambience stand out.

- **Palette:** nature is soft and irregular (clicks, chirps, groans, growls, bubbles, currents, distant tectonic rumbles). The sub and infrastructure are mechanical and rhythmic (whirs, rumbles, clanks).
- **Sound carries information:** leaks hiss in 3D, hull creaks worsen with depth like an audio pressure gauge, and each creature is identifiable by ear.
- **The sonar operator hears what no one else does** and has to relay it out loud, which is itself a risk.
- **Silence is a set piece.** During silent running, the mix falls to breathing and the ocean. Keep real dynamic range for those moments.
- **Voices change with context:**

| Context | Treatment |
| --- | --- |
| Inside the sub | Sharp, metallic, short echo |
| Dive suit radio | Muffled and tinny |
| Radio from inside a facility | Faint and static-laced; degrades with walls and distance |
| Through the hull | Heavy, low, muffled thud |
| In person inside a facility | Larger, more open echo |

## Visual direction

Low-poly models with crisp, clean rendering. No grain, static, dither or fuzzy filters. Lighting and atmosphere carry the mood, and detail can be added later.

- **Volumetric fog** gives underwater light beams real shape and a short reach. It is built into Godot 4.
- **Marine snow** drifting through the lights reads instantly as deep ocean.
- **Strong silhouettes.** With little visible detail, creatures and structures are recognized by shape, so shape matters more than texture. Restrained surface treatment is welcome where it supports silhouette and never competes with it: the sub interior's worn industrial metal has low-contrast panel lines and light wear, and no grain or noise filter.
- **Light is gameplay.** The difference between white and red light should be obvious at a glance.
- **Infrastructure looks overbuilt:** rivets, heavy hatches, clear labels, backup systems, maintenance logs. Industrial, never sleek. The feel (industrial, utilitarian, competent) matters more than any specific detail.
- **Brutalist architecture:** Raindrop builds in smooth, angular concrete and steel. Its stations have massive stacked slabs, cantilevered tiers, splayed struts, repeated ribs, and deep-set ribbon windows. Hard angular structures stand against soft, sloping organic terrain.
- **Soft neon on the architecture:** orange, blue and green light in lines, slots and windows, fading quickly into the dark. It sets the infrastructure apart from nature and shows how vast and isolating the ocean is. The sub's working lights stay white or red.
- **The sub is modern and utilitarian (M7).** A near-future research sub: matte, muted surfaces, backlit gauges, hidden cove lighting (lights behind fascias at the top of the walls, so light spills down the surfaces) with occasional point sources, holographic map displays, a glass dome over the pilot. Cabin lights dim so the crew can see out. The hull is generated from `assets/models/vehicles/sub_interior/program.yaml` by `tools/build_sub_hull.py`.
- **The water surface and surfacing light (M9).** The surface at depth 0 is a crisp low-poly wave plane, translucent and rippled: from below it transmits the sky (sun disc or bright patch), from above it reflects it; it is never drawn inside the hull. Ambient and directional light rise over the last 40 m of ascent, so the approach to the surface is visible before the gauge shows it: strong by day, faint at night. Day and night are Resource presets (sky, light colour, intensity, surface colours), day by default, no cycle. A developer switch (F7) flips the preset.
- **Terrain reads as real seabed.** Dive sites are continuous heightfields from a site spec (a sculpted profile plus constraints), with eroded-looking analytic detail (smooth-blended profile, strata bands, domain-warped, slope-damped noise), grid erosion passes, tuned in an in-game terrain lab. Not stacked boxes. The macro shape now lives in a `SiteSpec` Resource (`src/site/presets/canyon.tres`, with `SiteConstraint` as the base for rules). `FlatPad`, `Corridor` and `ClearColumn` constraints are applied as soft masks (detail fades inside them, the combined mask protects those cells from erosion), a validator flags conflicts, and the scan objective's position is read from the preset's `FlatPad` rather than hard-coded. Erosion (`ErosionParams`, `TerrainErosion`) samples the analytic generator onto a grid, runs a seeded hydraulic droplet pass (sediment-carrying particles carve gullies, flow diverted around protected cells, sediment conserved), a thermal pass (slump above a talus angle) and a deposition-settle pass (flat ground relaxes, steep cells untouched), never changes cells inside a constraint mask, and serves `height_at` by bilinear sampling; it is seeded and off by default, leaving `height_at` analytic. The terrain lab is a queued concept (#123).
- Full detail and references are in [Art direction](docs/art_direction.md).

## Technical architecture

- **Engine:** Godot 4, the latest stable release when work starts. That was 4.7 at last check, with 4.8 in development ([GameDev.net](https://gamedev.net/news/4477/)).
- **Language: typed GDScript everywhere,** with type hints on every variable and function. GodotSteam has no official C# build; C# support goes through a community bindings project in open beta ([GodotSteam docs](https://godotsteam.pages.dev/getting_started/what_are_you_making)). Rewrite isolated hot spots later only if profiling demands it.
- **Platform:** PC on Steam. Being Steam-only is fine.
- **Python tools exception (#220):** game code and the Godot editor plugin are typed GDScript, but tooling under `tools/` may be Python, run with `uv`.
- **Asset pipeline:** `tools/asset_pipeline/` is a Python backend (`uv run asset <command>`) that takes an asset from concept art to a game-ready model: one command per stage, a manifest (`assets/models/<slug>/asset.yaml`) with provenance and lineage, and image, 3D and prompt-writer providers selected in `providers.yaml`. A Godot editor plugin (`addons/asset_studio/`) is its interface. Rejected variants and raw provider meshes stay in the git-ignored `.asset_work/`.
- **Export:** the Asset Studio plugin and the Python backend are development tools and are excluded from game exports.

### Networking

- **Listen server.** One player hosts through a Steam lobby, and friends join through Steam. GodotSteam's multiplayer peer plugs into Godot's built-in multiplayer (spawners, synchronizers, RPCs).
- **The host is authoritative.** It simulates the sub's physics, creatures, noise and objectives. Clients send intents, such as setting valve 3 to 0.4.
- **Build on local networking first.** Develop with Godot's ENet peer and several local instances, then swap to Steam. Keep peer creation behind one function.
- A slow, heavy sub tolerates latency well.

### Walking inside a moving sub

Decide this on day one: the crew moves in the sub's own frame of reference, so the sub's motion never slides players around. Tilt changes the apparent direction of gravity, which also makes trim easy to build.

**Decided:** the interior is a still scene. The sub's hull model moves through the outside world, and the view outside is composed from the sub's transform. Player positions sync in sub-local space, never world space.

### Interactables

One reusable component for every physical control: a value, a range, a noise profile tied to how fast it changes, and network sync. The player moving it sees the response immediately, and the host confirms it.

### Noise system

- Runs on the host. Sources register their loudness, which sums into the sub's noise level. Ambient zones add background, and creatures query the result.
- Voice loudness is measured on the host from the voice data it receives, so no client can fake being quiet. **Decided (#8):** the prototype has no in-game voice, so each player's machine measures its own mic and sends the loudness to the host. Once Steam Voice is in, the same function moves to the host. The first playtest runs uncalibrated; a "speak normally" calibration step is a deferred option (#17) if mic differences prove unfair.

### Voice

- Steam Voice through GodotSteam: capture with getVoice, send, then decompressVoice, which returns raw 16-bit mono audio at any rate from 11,025 to 48,000 Hz ([Steamworks docs](https://partner.steamgames.com/doc/api/ISteamUser)).
- Feed each player's voice into a 3D audio source, then route it through audio buses with filters and reverb set by context.

### Content and saves

- Creatures, equipment, objectives and dive sites are Godot Resources, so they can be tuned without code changes.
- The host owns the expedition save and writes it between dives.

### Conventions for Claude Code

- Small, single-purpose scenes; signals over hard references between systems.
- Autoloads only for true globals: networking, noise and audio routing.
- No HUD elements unless the design calls for an in-world screen.

## First prototype

The prototype answers one question: is it tense and fun to coordinate a sub when talking is dangerous? It should be light enough to build quickly while still exercising every core system.

### In scope

- [x] Two to four players over local ENet networking
- [x] Walking inside the sub in its own frame of reference
- [x] Pilot steering and diving planes on WASD
- [x] Engine order telegraph at the engineering station (replaced in M7 by a throttle at the helm)
- [x] Ballast valves that flood and blow the tanks
- [x] One recurring leak with a field patch
- [x] The noise system and two-needle gauge, with each player's mic loudness feeding the noise level
- [x] One blind, sound-hunting apex monster with the full escalation ladder
- [x] Minimal passive sonar: a hydrophone the operator turns, with directional audio only they hear. No active ping and no 3D display. (Later, the bearing display on the station bezel adds a chart overlay of marks; there is still no sonar picture.) This is the hardest system to calibrate, so expect to rework it many times.
- [x] One small vertical map with two or three shelves
- [x] One objective: a scan taken from the sub
- [x] A played descent and ascent; the dive ends on surfacing

### Out of scope

Steam integration and in-game voice, expeditions, cargo, divers, facilities, upgrades, other creatures, the hub, the field guide, and an art pass. Until in-game voice exists, playtest crews talk over an external voice app while the game measures each player's mic locally.

### What success looks like

- Crews start whispering, calling out tersely and going silent without being told to.
- Players can read where the monster is on the escalation ladder from sound alone.
- After a loss, the crew can say what gave them away.

## Open questions and things to watch

### Still open

- Expedition routing: free routing (the lean) or a node map
- Whether to add a fourth loop above expeditions, and how long it would run
- How sonar is actually operated; this is the highest-risk system
- Whether recoveries get a hard cap, or the sub's condition alone ends an expedition
- Whether the thermocline and rhythmic-detection mechanics make the cut
- The field patch mini-game
- ~~Whether charts stays its own station~~ Decided in M7: the map table is a shared holographic chart anyone can use; the pilot has a heading-up copy.
- Whether to lock out crews of two. The lean is no lock, but no design effort goes toward two-person crews: target four, keep three viable.
- Distinct sub types and hardware variants

### Watch in playtesting

- Crews losing the sub on purpose to reset damage, which the recovery model is meant to prevent
- Upgrades making later play too easy
- Sonar becoming a chore
- Too many creatures cluttering the tension
- Whether every loss feels earned rather than random
- Whether dives actually land near 30 minutes. A scripted autopilot with no monster finishes the prototype dive in about 7.5 minutes (it was about 8 before M7 doubled the sub's responsiveness). A real crew hiding from the apex will take longer, but the prototype site is likely well short of 30.

## Sources

- [NOAA Ocean Explorer: the Medusa red-light camera](https://oceanexplorer.noaa.gov/?p=5896)
- [WHOI: the stoplight loosejaw](https://www.whoi.edu/?p=606840)
- [GameDev.net: Godot 4.7.1 release](https://gamedev.net/news/4477/)
- [GodotSteam: choosing a version](https://godotsteam.pages.dev/getting_started/what_are_you_making)
- [Steamworks: ISteamUser and Steam Voice](https://partner.steamgames.com/doc/api/ISteamUser)
