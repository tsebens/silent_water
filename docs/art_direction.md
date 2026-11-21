# Art direction

How Silent Water should look. The design doc's *Visual direction* section is the summary; this file is the detail, and the reference for anyone making assets. Update both when the direction changes.

## In one line

**Brutalist concrete and steel, lit by soft fading neon, alone in a vast dark ocean.**

## Feel first

Everything Raindrop built must feel **industrial, utilitarian and competent**. That feel matters more than any specific detail. Rivets, bolts and labels are tools for getting there, not requirements.

The genre's usual look is sleek, rounded and cyberpunk, and most of the early mood board shares it. Borrow that look's lighting and polish, but not its smooth consumer-product shapes.

## Architecture: brutalism under pressure

Raindrop's infrastructure follows brutalist construction: massive, honest, built to outlast the people who built it.

- **Materials:** smooth, angular concrete and steel. Board-marked or poured concrete, steel railings, trusses and frames. Little ornament; structure is the decoration.
- **Massing:**
  - heavy horizontal slabs stacked and stepped outward, with cantilevered tiers wider than their base
  - deep overhangs with coffered or ribbed undersides
  - repeated vertical fins and ribs
- **Support:** thick columns and splayed, angled struts that make the load path visible. Buildings lifted off the ground on pilotis or legs.
- **Openings:** long ribbon windows or slots set deep in the mass, never large glass domes. Glass is a small, recessed exception in a wall of concrete.
- **Repetition and modularity:** identical bays, modules and ribs repeated along a structure. This reads as engineered and makes buildings easy to build from parts.
- **Contrast with nature:** architecture is hard-edged, flat-faced and angular, while the terrain is soft, sloping and organic. A station should never be mistaken for rock, even as a silhouette.

## Light: soft fading neon

- **Colors:** soft neon in **orange, blue and green**. Use them as lines, strips, slots and small point lights on the architecture, not as floodlighting.
- **Soft, not cyberpunk:** low intensity, wide glow, no hard magenta-and-cyan signage. Light should seem to come from the structure, through its slots and windows and along its edges.
- **Fading reach:** colored light falls off quickly into the fog. A station is a few glowing lines and windows hanging in the dark, which shows how vast the ocean is and how isolated the infrastructure is.
- **The ocean around it stays dark:** deep teal to black, marine snow, volumetric beams with short reach.
- **White and red light remain gameplay** (see the design doc). The neon palette belongs to the architecture; the sub's working lights are white or red.

### Suggested color roles (to confirm)

Not yet decided. One option:

- **orange:** working, powered, safe
- **blue:** idle or passive systems
- **green:** restored or friendly infrastructure

Fixed roles would let players read a site's state from a distance.

## The sub

The sub is a different object from the stations. Per M7 it's a **modern, utilitarian near-future research sub**:
- matte, muted surfaces
- backlit gauges
- hidden cove lighting at the top of the walls, with occasional point sources
- holographic map displays
- a glass dome over the pilot

Its hull is built in Onshape (`assets/media/sub/`) and converted with `tools/convert_sub.py`, so the hull shape is set there, not here.

The sub and the stations still share one feel: industrial, utilitarian, competent. The sub is the crew's well-kept working tool; the stations are the massive, aging network it serves. Brutalist massing belongs to the stations, not the sub.

### Interior metal

Interior surfaces (hull shell, deck, hatch and fittings) share one procedural material, `src/sub/worn_metal.gdshader`, assigned per part by `SubModel`. It is matte industrial metal: low-contrast panel seams, light scratches, and edge and walkway wear. It is crisp, with no grain or noise filter, and it supports the silhouette rather than competing with it. Glass and displays keep their own looks; the exterior is untouched.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `base_tone` | per part (shell `0.15,0.17,0.18`, fittings `0.24,0.27,0.29`) | Base colour |
| `wear_amount` | 0.35 | 0 pristine to 1 heavily worn (scratches, seam edges, walkway) |
| `scale` | 1.0 | Pattern density; panels are 1 m / scale |
| `metallic_amount`, `roughness_amount` | per part | Surface response |
| `walkway_height` | 0.35 | Local height (m) below which floor wear builds up |

## Props and equipment

Props inside the sub follow the sub. They're compact and purposeful, matching its matte finish and lighting, with heavy-duty modular parts and a clear function at a glance.

Equipment that belongs to the network, such as sensor arrays, cable junctions, buoys and station hardware, follows the architecture: angular, slab-like, overbuilt.

Everything is worn by age and pressure, never sloppy.

## References

Kept in `assets/media/architecture/` (to be added):

| File | Reference | What to take from it |
| --- | --- | --- |
| `geisel_library.jpg` | Geisel Library, UC San Diego (William Pereira) | Stepped, cantilevered concrete tiers on splayed angled struts; ribbon glazing set deep in the mass |
| `barbican_estate.jpg` | Barbican Estate, London | Long repeated concrete balconies on heavy pilotis; massive horizontal bands; structure meeting water |
| `national_theatre.jpg` | National Theatre, London (Denys Lasdun) | Board-marked concrete; stacked horizontal terraces with coffered soffits; tower blocks; simple steel handrails |
| `underwater_station.jpg` | Concept art from the film *Underwater* (2020) | A heavy station on the seafloor, truss tower and tracked modules; small cool lights in near-total dark; diver for scale |
| `rosander_seafloor_modules.jpg` | Concept art by Patrik Rosander | Monolithic ribbed angular modules on a sloping seabed; tiny warm window lights; fog swallowing distance |

The earlier mood board in `assets/media/` remains a reference for lighting, palette and underwater atmosphere. Where it shows sleek, rounded forms, this file takes precedence.

## Style bible

The asset pipeline's prompt blocks and class profiles live in `assets/style_bible/` (see its `README.md`). They are seeded from this file; when the direction changes here, update them too.
