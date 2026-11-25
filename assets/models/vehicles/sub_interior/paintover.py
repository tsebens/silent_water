"""Paint-over concepts of the sub interior from the greybox blockout renders.

Run from tools/asset_pipeline: uv run -q python ../../assets/models/vehicles/sub_interior/paintover.py <out_dir> <shot> [...] [--n N]
Needs GEMINI_API_KEY. Stopgap until Asset Studio can paint over scene shots (#333); round 2's picks are in concept/.
Calls the pipeline's google-pro image adapter (Gemini 3 Pro Image) with the render as the first image and the
locked cockpit and map table concepts as style anchors.
"""
from __future__ import annotations

import sys
from pathlib import Path

from asset_pipeline.adapters.google_image import GoogleImage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RENDERS = HERE / "renders" / "blockout"
ANCHORS = [ROOT / "assets/models/cockpit/concept/cockpit_primary.png",
           ROOT / "assets/models/map_table/concept/map_table_primary.png"]

COMMON = """\
Paint over the FIRST image: a colour-coded greybox render of the interior of a small four-person research
submarine (10 m long, 3.8 m wide, 3 m tall inside the hull). KEEP its camera, composition, perspective and every
block's position and proportions exactly. Turn the blocks into finished concept art of the real equipment.

Colour key of the greybox: grey curved shell = the inside of the pressure hull; dark grey floor = deck plates;
orange boxes = equipment panels and consoles; green = the map table; light cyan wireframes = holograms
(draw them as light, not as wire cages); blue = seats; near-black slabs = screens; teal behind the bow ring =
open water seen through a large acrylic dome; tall grey cylinders = crew figures (draw them as people).

Style: the second and third images are the locked concept art; match their look exactly. A modern near-future
working sub, not a WW2 submarine: welded steel and aluminium, powder-coated matte grey with safety-orange
accents, machined frames and ribs, braided cable looms, guarded toggles, rocker switches and LED lamps in clean
panel layouts, engraved label plates with no legible text. Hidden cove lighting along the top of the walls,
backlit gauges, cool white working light, the holograms a soft cyan. Wear is scuffs and worn paint, never rust.
Avoid rivets, brass, valve hand-wheels, stencilled lettering, caged bulb lamps, bare pipework as texture,
legible text or numbers, and lens effects.

Do not add equipment, furniture, doors, windows or people that are not blocks in the greybox, and do not leave
any block out. Displays show simple abstract shapes and lines, never digit readouts. Prefer flat backlit panels,
toggles and LED lamps over round analogue dial gauges. No rust; clean, well-kept paint with worn edges.
The bow dome is one unbroken hemisphere of clear acrylic bulging forward of a heavy steel ring, no frames or
mullions in the glass; the pilot's floor inside it is one step down and partly glass.
"""

SHOTS = {
    "midships_forward": """\
This shot: standing aft in the crowded midships compartment, looking forward toward the bow. Left (port): the
map table, a D-shaped desk-height table built into a bay in the hull wall, with a curved slab of holographic
seafloor terrain on it and an instrument cowl above. Right (starboard): the sonar desk and its forward-facing
seat, then the tall countermeasures panel nearest the viewer. Ahead: the heavy steel dome ring and, through
the unbroken acrylic dome (no mullions), the pilot alone in a seat with armrest controls, the dark sea beyond.
Cramped, lived-in, competent.""",
    "sonar_view": """\
This shot: seated at the sonar desk, looking forward and down. Right: the sonar console, a 55 cm screen in a
deep bezel on a steeply raked desk (the screen shows abstract sonar contacts as simple shapes, no text).
Ahead-left, a metre away: the back of the pilot's seat with its elbow rail and a small 20 cm cylinder of
hologram, and beyond it the dome ring and open water through the acrylic dome.""",
    "map_operator_view": """\
This shot: standing behind the map table's operator, looking down at the table. The D-shaped table is built
into a bay in the port hull wall; on it, a curved slab of holographic seafloor terrain fills the top, crisp
edged, 0.7 m tall, with a few glowing waypoint pins and a thin route line. Above it, the instrument cowl
wraps round like a cab. The operator's console is built into the front edge: trackball, zoom lever,
guarded toggles. Everyone at this table stands.""",
    "engineering_aft": """\
This shot: from the watertight bulkhead hatch looking aft into engineering, the mechanic's end of the boat,
lower and tighter as the hull tapers. The far
end is the closed, curved steel end cap of the pressure hull (the pale oval in the greybox): a solid wall with
pipe runs and frames, NOT a door, hatch or window. Panels for power and life support either side, the ballast valve panel
on the right (port), a yellow drop-weight release lever on the left, the bilge well (dark red) in the floor with its pump at the far end.
Louder and more industrial than midships, but still clean, modern and well kept.""",
    "map_observer_view": """\
This shot: standing in the aisle across from the map table, looking at it. The D-shaped table in its bay in
the port hull wall, the curved hologram slab of seafloor terrain on it, crisp edged, the instrument cowl
above; the dome ring and the pilot's seat are at the right edge of frame.""",
    "pilot_view": """\
This shot: the pilot's own view, seated alone in the acrylic dome, looking out and down. Glass all round and
underfoot, so the dark seafloor below is visible; at the bottom of frame the two elbow rails with armrest
joysticks and, between them on the forward end of the rail, a small 20 cm cylinder of hologram showing the
sub at its centre. Nothing blocks the view out.""",
}


def main() -> None:
    args = sys.argv[1:]
    n = 1
    if "--n" in args:
        k = args.index("--n")
        n = int(args[k + 1])
        del args[k:k + 2]
    out_dir = Path(args[0])
    out_dir.mkdir(parents=True, exist_ok=True)
    gen = GoogleImage(model="gemini-3-pro-image")
    for shot in args[1:]:
        src = RENDERS / f"blockout_{shot}.jpg"
        prompt = COMMON + "\n" + SHOTS[shot]
        for v in range(n):
            out = out_dir / f"{shot}_v{v + 1}.png"
            try:
                gen.edit(prompt, src, ANCHORS, out)
                print("OK", out, gen.last_usage, flush=True)
            except Exception as exc:  # keep going with the other shots
                print("FAIL", shot, v + 1, exc, flush=True)


main()
