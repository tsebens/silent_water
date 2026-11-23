"""Draw and check the sub interior program (program.yaml): top, side and front views plus a clearance report.

    uv run --project tools/asset_pipeline python assets/models/vehicles/sub_interior/plan.py [out_dir]

Writes plan_top.png, plan_side.png, plan_front.png and clearance.txt to out_dir (default: this folder's
renders/ subfolder). The hull is a superellipse from the top and from the front, so the deck width and the
headroom are computed per station instead of being assumed.
"""
from __future__ import annotations

import sys
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent


def superellipse_half(extent: float, t: float, p: float) -> float:
    """Half-extent of a superellipse |u|^p + |v|^p = 1 at normalised position t in [-1, 1]."""
    t = min(abs(t), 1.0)
    return extent * (1.0 - t ** p) ** (1.0 / p)


class Hull:
    def __init__(self, h: dict, compartments: list | None = None) -> None:
        self.compartments = compartments or []
        self.L, self.W, self.H = h["length_m"], h["width_m"], h["height_m"]
        self.pp, self.ps = h["plan_exponent"], h["section_exponent"]
        self.pz = h.get("profile_exponent", self.pp)
        self.wall, self.deck_up = h["wall_m"], h["deck_above_bottom_m"]

    def half_width_at(self, z: float) -> float:
        """Outer half-width at hull station z (plan view)."""
        return superellipse_half(self.W / 2, z / (self.L / 2), self.pp)

    def half_height_at(self, z: float) -> float:
        """Outer half-height at z: its own superellipse along the length (profile_exponent), so the side
        profile can stay fuller than the plan before closing in at the bow and stern."""
        return superellipse_half(self.H / 2, z / (self.L / 2), self.pz)

    def section_half_width(self, z: float, y: float) -> float:
        """Inner half-width at height y (0 = hull centre) in the cross-section at z."""
        hw, hh = self.half_width_at(z) - self.wall, self.half_height_at(z) - self.wall
        if hh <= 0 or abs(y) >= hh:
            return 0.0
        return superellipse_half(hw, y / hh, self.ps)

    def deck_y(self, z: float | None = None) -> float:
        """Floor height at z: the main deck, plus the compartment's floor_offset_m (the sunken cockpit)."""
        y = -self.H / 2 + self.deck_up
        if z is not None:
            for c in self.compartments:
                if c["z"][0] <= z <= c["z"][1]:
                    return y + c.get("floor_offset_m", 0.0)
        return y

    def deck_half_width(self, z: float) -> float:
        return self.section_half_width(z, self.deck_y(z))

    def clear_height(self, z: float, x: float = 0.0) -> float:
        """Inner headroom above the deck at (x, z)."""
        hw, hh = self.half_width_at(z) - self.wall, self.half_height_at(z) - self.wall
        if hw <= 0 or abs(x) >= hw:
            return 0.0
        top = superellipse_half(hh, x / hw, self.ps)
        return max(0.0, top - self.deck_y(z))


def place(item: dict, hull: Hull) -> tuple[float, float, float, float]:
    """(x0, x1, z0, z1) of an item on the deck."""
    along, across = item["footprint"]
    z0, z1 = item["z"] - along / 2, item["z"] + along / 2
    if "x" in item:
        x = item["x"]
        return x - across / 2, x + across / 2, z0, z1
    side = item.get("side", "centre")
    fw = min(hull.deck_half_width(z0), hull.deck_half_width(z1))
    if side == "port":
        return -fw, -fw + across, z0, z1
    if side == "starboard":
        return fw - across, fw, z0, z1
    return -across / 2, across / 2, z0, z1


def clearance_report(spec: dict, hull: Hull) -> list[str]:
    c = spec["clearances"]
    items = spec["stations"] + spec["features"]
    lines, fails = [], 0
    for it in items:
        x0, x1, z0, z1 = place(it, hull)
        # Narrowest deck width across the item's length, and what other items occupy at the same z.
        fw = min(hull.deck_half_width(z) for z in (z0, it["z"], z1))
        occupied = [(x0, x1)]
        for other in items:
            if other is it:
                continue
            ox0, ox1, oz0, oz1 = place(other, hull)
            if oz0 < z1 and oz1 > z0:
                occupied.append((ox0, ox1))
        occupied.sort()
        gaps, cursor = [], -fw
        for a, b in occupied:
            if a > cursor:
                gaps.append(a - cursor)
            cursor = max(cursor, b)
        if fw > cursor:
            gaps.append(fw - cursor)
        best = max(gaps) if gaps else 0.0
        # An aisle past an item is only needed if something lies further toward that end of the hull:
        # nobody walks past the pilot's seat or the bilge well at the stern.
        toward_bow = it["z"] < 0
        beyond = [o for o in items if o is not it and ((o["z"] < z0) if toward_bow else (o["z"] > z1))]
        need_both = it.get("kind") == "table"
        if need_both:
            left = x0 - max([b for a, b in occupied if b <= x0 + 1e-6] + [-fw])
            right = min([a for a, b in occupied if a >= x1 - 1e-6] + [fw]) - x1
            ok = left >= c["walk_around_m"] and right >= c["walk_around_m"]
            msg = f"walk-round gaps {left:.2f} m / {right:.2f} m (need {c['walk_around_m']} each side)"
        elif not beyond:
            ok = True
            msg = f"end of the hull, no aisle needed (widest gap {best:.2f} m)"
        else:
            ok = best >= c["aisle_min_m"]
            msg = f"widest free aisle {best:.2f} m (need {c['aisle_min_m']})"
        # The item itself must fit on its floor: its footprint inside the deck's width at both ends.
        fits = all(hull.deck_half_width(z) >= max(abs(x0), abs(x1)) - 1e-6 for z in (z0, z1))
        if not fits:
            ok = False
            msg = f"does not fit: deck {2 * fw:.2f} m wide at its ends, needs |x| up to {max(abs(x0), abs(x1)):.2f} m; " + msg
        head = hull.clear_height(it["z"], 0.0)
        head_ok = head >= c["head_clear_m"] or it.get("kind") in ("well",)
        status = "ok  " if ok and head_ok else "FAIL"
        fails += status == "FAIL"
        lines.append(f"{status} {it['id']:<16} z={it['z']:+.2f}  deck {2 * fw:.2f} m  {msg}  headroom {head:.2f} m")
    lines.append(f"{fails} problem(s)")
    return lines


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf", size)
    except OSError:
        return ImageFont.load_default()


COLOURS = {"seat": (90, 160, 220), "panel": (230, 150, 60), "table": (90, 200, 130), "well": (200, 90, 90),
           "floor_hatch": (240, 220, 90), "ladder": (180, 180, 200), "storage": (120, 120, 130),
           "release_lever": (220, 200, 60)}
ROOMS = {"cockpit": (40, 70, 95), "forward": (45, 60, 55), "midships": (62, 56, 44), "bulkhead": (95, 95, 95),
         "engineering": (72, 46, 46)}
BG, LINE, TEXT = (22, 28, 34), (130, 150, 160), (225, 230, 232)


def draw_top(spec: dict, hull: Hull, out: Path) -> None:
    S = 105
    W, H = int(hull.L * S + 260), int(hull.W * S + 220)
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    ox, oy = 130, 130 + hull.W * S / 2
    zx = lambda z: ox + (z + hull.L / 2) * S  # noqa: E731
    xy = lambda x: oy + x * S  # noqa: E731
    steps = [(-hull.L / 2 + hull.L * i / 200) for i in range(201)]
    outer = [(zx(z), xy(-hull.half_width_at(z))) for z in steps] + [(zx(z), xy(hull.half_width_at(z))) for z in reversed(steps)]
    d.polygon(outer, outline=LINE)
    for c in spec["compartments"]:
        a, b = c["z"]
        zs = [a + (b - a) * i / 20 for i in range(21)]
        poly = [(zx(z), xy(-hull.deck_half_width(z))) for z in zs] + [(zx(z), xy(hull.deck_half_width(z))) for z in reversed(zs)]
        d.polygon(poly, fill=ROOMS.get(c["id"], (50, 50, 50)), outline=(150, 150, 150))
        d.text((zx(a) + 4, xy(-hull.W / 2) - 22), c["id"], fill=TEXT, font=font(14, True))
    f = font(13)
    for it in spec["stations"] + spec["features"]:
        x0, x1, z0, z1 = place(it, hull)
        box = [zx(z0), xy(x0), zx(z1), xy(x1)]
        if it.get("kind") == "floor_hatch":
            d.ellipse(box, outline=COLOURS["floor_hatch"], width=3)
        else:
            d.rectangle(box, fill=COLOURS.get(it.get("kind"), (90, 90, 90)), outline=(235, 235, 235))
        d.text((zx(z0), xy(x1) + 2), it["id"], fill=TEXT, font=f)
    for c in spec["compartments"]:
        if c.get("floor_offset_m"):
            d.text((zx(c["z"][0]) + 4, xy(hull.W / 2) + 4), f"floor {c['floor_offset_m']:+.2f} m", fill=(200, 170, 90), font=f)
    d.line([ox, H - 40, ox + S, H - 40], fill=TEXT, width=3)
    d.text((ox + S + 8, H - 48), "1 m", fill=TEXT, font=f)
    d.text((zx(-hull.L / 2) - 50, oy - 8), "BOW", fill=TEXT, font=font(14, True))
    d.text((zx(hull.L / 2) + 8, oy - 8), "STERN", fill=TEXT, font=font(14, True))
    d.text((ox, 16), f"Top view at deck level: hull {hull.L} x {hull.W} x {hull.H} m; port is up", fill=TEXT, font=font(16, True))
    d.text((ox, 40), "blue seat  orange panel  green table  red bilge well  yellow ring = lock-out trunk  grey = ladder/lockers",
           fill=(170, 180, 185), font=f)
    img.save(out)


def draw_side(spec: dict, hull: Hull, out: Path) -> None:
    S = 105
    W, H = int(hull.L * S + 260), int(hull.H * S + 300)
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    ox, oy = 130, 150 + hull.H * S / 2
    zx = lambda z: ox + (z + hull.L / 2) * S  # noqa: E731
    yy = lambda y: oy - y * S  # noqa: E731
    steps = [(-hull.L / 2 + hull.L * i / 200) for i in range(201)]
    outer = [(zx(z), yy(hull.half_height_at(z))) for z in steps] + [(zx(z), yy(-hull.half_height_at(z))) for z in reversed(steps)]
    d.polygon(outer, outline=LINE)
    deck = hull.deck_y()
    zs = [z for z in steps if hull.deck_half_width(z) > 0.05]
    for c in spec["compartments"]:
        a, b = max(c["z"][0], zs[0]), min(c["z"][1], zs[-1])
        fy = hull.deck_y((a + b) / 2)
        d.line([zx(a), yy(fy), zx(b), yy(fy)], fill=(200, 170, 90), width=3)
    head = spec["clearances"]["head_clear_m"]
    d.line([zx(zs[0]), yy(deck + head), zx(zs[-1]), yy(deck + head)], fill=(200, 80, 80), width=1)
    d.text((zx(zs[0]), yy(deck + head) - 16), f"{head} m headroom line", fill=(200, 80, 80), font=font(12))
    # conning tower over the ladder, and the lock-out chamber under the floor hatch
    tower = next(i for i in spec["features"] if i["id"] == "tower_ladder")
    tz = tower["z"]
    top = hull.half_height_at(tz)
    d.rectangle([zx(tz - 0.6), yy(top + 0.9), zx(tz + 0.6), yy(top - 0.05)], outline=LINE, width=2)
    d.text((zx(tz - 0.6), yy(top + 0.9) - 18), "conning tower + top hatch", fill=TEXT, font=font(12))
    trunk = next(i for i in spec["features"] if i["id"] == "lock_out_trunk")
    k = trunk["z"]
    d.rectangle([zx(k - 0.45), yy(deck), zx(k + 0.45), yy(-hull.half_height_at(k) - 0.25)], outline=COLOURS["floor_hatch"], width=2)
    d.text((zx(k + 0.5), yy(-hull.half_height_at(k) - 0.1)), "lock-out chamber (bottom hatch to sea)", fill=COLOURS["floor_hatch"], font=font(12))
    person, seated_eye = 1.75, 1.2
    for it in spec["stations"]:
        fy = hull.deck_y(it["z"])
        tall = seated_eye + 0.1 if it.get("kind") == "seat" else person
        d.rectangle([zx(it["z"] - 0.15), yy(fy + tall), zx(it["z"] + 0.15), yy(fy)], outline=(120, 170, 220))
        if it.get("kind") == "seat":
            ey = fy + seated_eye
            d.ellipse([zx(it["z"]) - 4, yy(ey) - 4, zx(it["z"]) + 4, yy(ey) + 4], fill=(120, 220, 255))
        d.text((zx(it["z"] - 0.3), yy(fy) + 6), it["id"], fill=TEXT, font=font(11))
    d.line([zx(-hull.L / 2), yy(0), zx(-hull.L / 2 + 1.6), yy(0)], fill=(120, 220, 255), width=1)
    d.text((zx(-hull.L / 2), yy(0) - 16), "dome centre", fill=(120, 220, 255), font=font(11))
    d.text((ox, 16), "Side view: hull profile, deck (gold), 2 m headroom (red), 1.75 m crew figures (blue)", fill=TEXT, font=font(16, True))
    img.save(out)


def draw_front(spec: dict, hull: Hull, out: Path) -> None:
    S = 120
    z = next(i for i in spec["stations"] if i["id"] == "map_table")["z"]
    W, H = int(hull.W * S + 300), int(hull.H * S + 260)
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    ox, oy = W / 2, 130 + hull.H * S / 2
    hw, hh = hull.half_width_at(z), hull.half_height_at(z)
    pts = []
    for i in range(361):
        t = -1 + 2 * i / 360
        pts.append((ox + t * hw * S, oy - superellipse_half(hh, t, hull.ps) * S))
    for i in range(361):
        t = 1 - 2 * i / 360
        pts.append((ox + t * hw * S, oy + superellipse_half(hh, t, hull.ps) * S))
    d.polygon(pts, outline=LINE)
    deck = hull.deck_y()
    fw = hull.deck_half_width(z)
    d.line([ox - fw * S, oy - deck * S, ox + fw * S, oy - deck * S], fill=(200, 170, 90), width=3)
    for x in (-0.95, 0.0, 0.95):
        d.rectangle([ox + (x - 0.3) * S, oy - (deck + 1.75) * S, ox + (x + 0.3) * S, oy - deck * S], outline=(120, 170, 220))
    d.text((20, 16), f"Front section at the map table (z={z:+.2f}): deck {2 * fw:.2f} m wide, "
                     f"headroom {hull.clear_height(z):.2f} m at the centre", fill=TEXT, font=font(15, True))
    img.save(out)


def main() -> None:
    spec = yaml.safe_load((HERE / "program.yaml").read_text(encoding="utf-8"))
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "renders"
    out.mkdir(parents=True, exist_ok=True)
    hull = Hull(spec["hull"], spec["compartments"])
    draw_top(spec, hull, out / "plan_top.png")
    draw_side(spec, hull, out / "plan_side.png")
    draw_front(spec, hull, out / "plan_front.png")
    report = clearance_report(spec, hull)
    (out / "clearance.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))


if __name__ == "__main__":
    main()
