# Concept brief: the sub's operational space (cockpit, sonar and map table)

A brief for a concept-art session. Bring the finished images back to the asset session to be saved
here and used as targets for the Blender build. Everything below is draft 4 of the interior program
(`program.yaml` in this folder); the plan views are in `renders/` (`plan_top.png`, `plan_side.png`).

## The game, in two lines

Silent Water is a first-person co-op submarine stealth game for four. The crew runs a small, old,
well-built research sub through deep-ocean sites while something enormous listens; talking keeps them
alive and gives them away. Nothing on board is abstract: information comes from physical instruments
and in-world screens, never a HUD.

## What this art is for

The **operational space**: the glass dome cockpit (pilot and sonar), and the front of midships
(countermeasures and the map table). This is where the crew spends most of a dive, so it sets the feel of
the whole interior. The images will be the visual target an agent builds toward in Blender, so
**proportions and placement matter as much as mood**. Keep to the layout below.

## Layout facts (keep these)

Units are metres. The sub is about 10 m long, 3.8 m wide and 3.0 m tall, an elliptical hull from the top
and from the front: wider than tall, full in the middle, rounding off at both ends. Crew are 1.75 m tall.

- **Glass dome cockpit at the bow.** A big bubble of glass, the forward end of the hull. Inside, its floor
  is **one step (0.2 m) below the main deck**, so a seated person's eyes sit at the dome's centre and
  the view out is even all round.
- **Pilot and sonar sit side by side**, shoulder to shoulder, facing forward into the dome: the pilot on
  the left (port), the sonar operator on the right (starboard). It's cramped, but it fits two.
- **No wall between the cockpit and midships.** The sunken cockpit opens straight back into the main
  deck. Standing crew behind them look over both seated heads and out through the dome.
- **Midships (behind the cockpit):** the **map table** stands free in the middle of the deck, about 1.1 m
  square, with walking room all round (it's about 2.8 m wide here, with 2.3 m of headroom).
  **Countermeasures** is a standing panel on the right-hand (starboard) wall, just forward of the table,
  so its operator can glance at the table to see their decoys work.
- Further aft (not the focus, but it can be glimpsed): a floor hatch to the lock-out chamber behind the
  table, a ladder up to the conning tower and lockers by a watertight bulkhead, and engineering beyond.
- The space should feel **cramped, busy and lived-in**: a catch-all. Pipes and cable runs overhead, kit
  stowed in every gap, nothing sleek.

## The three displays

There's one shared chart: terrain, contacts, pins and route waypoints. It appears three times, because
each station needs a **different scale**:

| Station | Size and placement | Shows | Why |
| --- | --- | --- | --- |
| Pilot | **Small**, low on the console, out of the forward view | Heading-up chart, near the sub | The dome is the pilot's view; the chart is a glance |
| Sonar | **Large and close**, filling much of the operator's view | Sonar picture **centred on the sub**, short range | It's their main input. The same controls (zoom, pins, waypoints) let sonar switch between reconnaissance and navigating |
| Map table | **A table you lean over** | Every scale: the whole site, down to finer detail than sonar | Crew planning; everyone sees everyone's marks |

**Open question, so explore it:** what the display technology looks like. Try two or three treatments
across the variants:
- **A.** Soft holographic projections (what the game has now).
- **B.** Old phosphor screens: green or amber vector-style CRTs in heavy bezels.
- **C.** A mechanical **pin-table** for the map table: a bed of pins rising into the terrain, with
  screens for the seats.

Pick whatever reads best for "old, well-built sub".

## Look and feel

- **Tristan's exterior vision:** `reference/exterior_vision_tristan.webp`. An old, rugged, overbuilt
  research sub with riveted plates, orange paint worn back to grey steel, external pipes, cables and lights.
  The interior should feel like the inside of *that* sub.
- **Interior:** painted steel, worn at the edges and walkways; exposed ribs and frames; valve wheels, gauges
  with backlit faces, toggle switches and labelled stencils (shapes of labels, **no legible text**). Small
  orange and yellow safety accents. Industrial, utilitarian, competent: never sleek, never cyberpunk.
- **Light:** dim, warm practical lights and backlit instruments, with the displays as strong light
  sources. Outside the dome, dark teal-black water with marine snow. A red-light "silent running" variant of
  one shot would be very useful: the game switches between white and red light.
- **Low-poly friendly:** strong, chunky shapes that read as silhouettes; avoid fine greebles.
- **Avoid:** text, logos and watermarks; people's faces in detail (figures for scale are fine, seen from
  behind); a glossy sci-fi bridge; huge glass walls other than the dome.

## Shots wanted

Use these cameras, so the art lines up with the blockout renders made later. Coordinates are sub-local
metres: z is along the hull (bow negative), y is height above the main deck, x is starboard positive.

1. **Hero: midships looking forward.** Standing eye height (y 1.65) just aft of the map table (z ≈ 0),
   on the centreline, looking toward the bow. Shows the table in the foreground, countermeasures on the
   right wall, and the sunken cockpit with both seats and the dome beyond.
2. **Pilot's view.** Seated at the pilot's seat, looking forward out of the dome: the small chart low on
   the console, controls in reach, the water beyond.
3. **Sonar's view.** Seated at the sonar seat: the large close display dominating, headset and hydrophone
   controls, the pilot just visible at the left edge.
4. **Over the shoulder.** Standing behind and between the two seats, looking down and forward: both seats,
   both displays, the step down, the dome.
5. **The map table.** Leaning over it from one side, with a second crew member opposite for scale.

For each shot, make **two or three variants** that differ in the display technology (A, B or C above).
Shot 1 matters most. If time is short, do it first, plus one red-light version.

## Bringing it back

Name files `cockpit_<shot>_<variant>.png`, e.g. `cockpit_hero_B.png` or `cockpit_sonar_A.png`, and note
which display treatment each variant uses. Bring them to the asset session as files: attached or committed,
not pasted inline, since inline images can't be saved. Say which you like, and why.
