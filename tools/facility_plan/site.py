# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "pillow>=10"]
# ///
"""Check and draw an exterior site program: unmanned infrastructure (e.g. assets/models/facilities/sensor_array/).

    uv run tools/facility_plan/site.py <program.yaml> [out_dir]

A site is elements standing on the seabed (boxes and cylinders), cables lying on it, service points where a diver
works, and the sub's hover point and approach. Writes into out_dir (default: `renders/` beside the program):
`site_plan.png` (top view), `site_elevation.png` (from the chasm), `report.txt` and `layout.json` (for
blockout.py). Exits non-zero when a check fails.

Checks, for play: every service point sits on its element, at a diver's working height, with clear water in front;
sensor posts are spread as an array; every cable joins its ends and is not too long; the approach corridor is clear;
the sub hovering at its work point keeps water under its keel. A site is not tied to terrain: the report gives the
flat pad it needs (`site.pad_margin_m` beyond its elements). If the program gives `site.ledge_edge_z` (a site drawn
at a chasm), everything must stand on the shelf.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageFont

TOL = 0.15
FACES = {"south": (0.0, -1.0), "north": (0.0, 1.0), "west": (-1.0, 0.0), "east": (1.0, 0.0)}
ROLE_COL = {"node": (150, 160, 168), "plinth": (95, 100, 106), "post": (175, 180, 186), "mast": (120, 124, 130),
            "beacon": (220, 70, 60), "pinger": (220, 70, 60), "light": (240, 200, 120), "cable_bay": (110, 115, 120),
            "fin": (140, 146, 152), "lamp_ring": (240, 170, 80), "emitter": (70, 74, 80)}


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf", size)
    except OSError:
        return ImageFont.load_default()


class Element:
    def __init__(self, d: dict) -> None:
        self.id, self.role = d["id"], d.get("role", "")
        self.base = float(d.get("base_y", 0.0))
        self.height = float(d["height"])
        self.tags = list(d.get("tags", []))
        if "box" in d:
            self.kind, self.box = "box", tuple(float(v) for v in d["box"])
        else:
            c = d["cylinder"]
            self.kind, self.at, self.r = "cyl", tuple(float(v) for v in c["at"]), float(c["radius"])

    @property
    def top(self) -> float:
        return self.base + self.height

    def dist(self, p: tuple[float, float]) -> float:
        """Horizontal distance from a point to the element's footprint (0 inside)."""
        if self.kind == "cyl":
            return max(0.0, math.dist(p, self.at) - self.r)
        x0, x1, z0, z1 = self.box
        dx = max(x0 - p[0], 0.0, p[0] - x1)
        dz = max(z0 - p[1], 0.0, p[1] - z1)
        return math.hypot(dx, dz)

    def on_surface(self, p: tuple[float, float]) -> bool:
        if self.kind == "cyl":
            return abs(math.dist(p, self.at) - self.r) <= TOL
        x0, x1, z0, z1 = self.box
        inx, inz = x0 - TOL <= p[0] <= x1 + TOL, z0 - TOL <= p[1] <= z1 + TOL
        return (inz and (abs(p[0] - x0) <= TOL or abs(p[0] - x1) <= TOL)) or (inx and (abs(p[1] - z0) <= TOL or abs(p[1] - z1) <= TOL))

    def bounds(self) -> tuple[float, float, float, float]:
        if self.kind == "cyl":
            return (self.at[0] - self.r, self.at[0] + self.r, self.at[1] - self.r, self.at[1] + self.r)
        return self.box

    def centre(self) -> tuple[float, float]:
        if self.kind == "cyl":
            return self.at
        x0, x1, z0, z1 = self.box
        return ((x0 + x1) / 2, (z0 + z1) / 2)


def seg_dist(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = 0.0 if dx == dz == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / (dx * dx + dz * dz)))
    return math.dist(p, (ax + t * dx, az + t * dz))


def path_len(path: list[tuple[float, float]]) -> float:
    return sum(math.dist(p, q) for p, q in zip(path, path[1:]))


class Site:
    def __init__(self, p: dict) -> None:
        self.p = p
        self.c = p.get("clearances", {})
        self.els = {e["id"]: Element(e) for e in p["elements"]}
        self.results: list[tuple[bool, str]] = []

    def check(self, ok: bool, msg: str) -> None:
        self.results.append((ok, msg))

    def hover_box(self) -> tuple[float, float, float, float]:
        sub = self.p["site"]["sub"]
        hx, hz = self.p["sub_hover"]["at"]
        L, W = sub["length_m"] / 2, sub["width_m"] / 2
        return (hx - L, hx + L, hz - W, hz + W) if self.p["sub_hover"].get("heading", "x") == "x" else (hx - W, hx + W, hz - L, hz + L)

    def run(self) -> list[str]:
        c = self.c
        lo, hi = c.get("service_height_m", [0.6, 1.8])
        room = c.get("service_room_m", 1.5)
        edge = self.p["site"].get("ledge_edge_z")
        if edge is not None:
            for e in self.els.values():
                x0, x1, z0, z1 = e.bounds()
                self.check(z0 >= edge - TOL or "overhang" in e.tags, f"{e.id} stands on the shelf (z from {z0:.1f})")
        b = [e.bounds() for e in self.els.values()]
        mg = self.p["site"].get("pad_margin_m", 5.0)
        self.pad = (min(v[0] for v in b) - mg, max(v[1] for v in b) + mg, min(v[2] for v in b) - mg, max(v[3] for v in b) + mg)
        self.check(True, f"needs a flat pad {self.pad[1] - self.pad[0]:.0f} x {self.pad[3] - self.pad[2]:.0f} m "
                         f"(x {self.pad[0]:.0f}..{self.pad[1]:.0f}, z {self.pad[2]:.0f}..{self.pad[3]:.0f}), front toward -z")
        for s in self.p.get("service_points", []):
            el = self.els[s["element"]]
            at = tuple(s["at"])
            self.check(el.on_surface(at), f"service point {s['id']} sits on {s["element"]}")
            h = s["y"] - s.get("stand_y", 0.0)
            self.check(lo <= h <= hi, f"service point {s['id']}: {h:.1f} m above where the diver hangs (band {lo}-{hi})")
            self.check(el.base <= s["y"] <= el.top, f"service point {s['id']} is within {s["element"]}'s height")
            fx, fz = FACES[s["faces"]]
            front = (at[0] + fx * room, at[1] + fz * room)
            blockers = [e.id for e in self.els.values() if e.id != el.id and e.dist(front) < 0.3 and e.base < s["y"] < e.top]
            self.check(not blockers, f"service point {s['id']}: {room} m of clear water in front" + (f" (blocked by {', '.join(blockers)})" if blockers else ""))
        posts = [e for e in self.els.values() if e.role == "post"]
        for i, a in enumerate(posts):
            for b in posts[i + 1:]:
                d = math.dist(a.centre(), b.centre())
                if d < c.get("post_spacing_m", 12.0) - TOL:
                    self.check(False, f"{a.id} and {b.id} are {d:.1f} m apart (array spacing {c.get('post_spacing_m')})")
        if "post_spacing_m" in c:  # an array: it has posts, spread out
            self.check(len(posts) > 0, f"{len(posts)} sensor posts, at least {c['post_spacing_m']:.0f} m apart")
        cabled = set()
        for cb in self.p.get("cables", []):
            path = [tuple(p) for p in cb["path"]]
            a, b = self.els.get(cb["from"]), self.els.get(cb["to"])
            self.check(a is not None and a.dist(path[0]) <= 0.6, f"cable {cb['id']} starts at {cb['from']}")
            if cb["to"] != "offsite":
                self.check(b is not None and b.dist(path[-1]) <= 0.6, f"cable {cb['id']} ends at {cb['to']}")
                L = path_len(path)
                self.check(L <= c.get("max_cable_m", 70.0), f"cable {cb['id']}: {L:.0f} m")
                cabled.add(cb["to"])
            if "break_at" in cb:
                bp = tuple(cb["break_at"])
                on = min(seg_dist(bp, p, q) for p, q in zip(path, path[1:]))
                self.check(on <= TOL, f"cable {cb['id']}'s break lies on its run")
        for p_ in posts:
            self.check(p_.id in cabled, f"{p_.id} is cabled to the node")
        # approach: a straight corridor, clear of everything taller than the seabed clutter
        ap = self.p.get("approach")
        if ap:
            a, b = tuple(ap["from"]), tuple(ap["to"])
            half = c.get("approach_width_m", 8.0) / 2
            hit = [e.id for e in self.els.values() if min(e.dist(q) for q in self._samples(a, b)) < half]
            self.check(not hit, f"approach from {a} to {b}, {2 * half:.0f} m wide, is clear" + (f" (crosses {', '.join(hit)})" if hit else ""))
        # hover: the sub's footprint over whatever is beneath, keel clear
        hb = self.hover_box()
        under = [e for e in self.els.values() if self._overlap(hb, e)]
        keel = max([e.top for e in under] + [0.0]) + c.get("hover_clear_m", 2.0)
        self.keel_y = keel
        self.check(True, f"sub hovers at {self.p['sub_hover']['at']} with its keel at y = {keel:.1f} m"
                         + (f" over {', '.join(e.id for e in under)}" if under else " over open seabed"))
        # report: distances a diver swims from the sub to each service point
        lines = []
        hx, hz = self.p["sub_hover"]["at"]
        sub = self.p["site"]["sub"]
        hatch_y = keel  # the lock-out trunk opens in the sub's floor
        for s in self.p.get("service_points", []):
            d = math.dist((hx, hatch_y, hz), (s["at"][0], s["y"], s["at"][1]))
            tags = ", ".join(t.replace("objective_", "") for t in s.get("tags", []))
            lines.append(f"{s['id']} ({tags}): {d:.0f} m swim from the sub's lock-out")
        return lines

    @staticmethod
    def _samples(a: tuple[float, float], b: tuple[float, float]) -> list[tuple[float, float]]:
        n = max(2, int(math.dist(a, b) / 0.5))
        return [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n + 1)]

    @staticmethod
    def _overlap(hb: tuple[float, float, float, float], e: Element) -> bool:
        x0, x1, z0, z1 = e.bounds()
        return min(hb[1], x1) > max(hb[0], x0) and min(hb[3], z1) > max(hb[2], z0)

    # ---- drawing --------------------------------------------------------------------------------------------------

    def draw_plan(self, out: Path) -> None:
        pts = [v for e in self.els.values() for v in (e.bounds()[0:2])], [v for e in self.els.values() for v in e.bounds()[2:4]]
        xs = pts[0] + [p[0] for cb in self.p.get("cables", []) for p in cb["path"] if cb["to"] != "offsite"]
        zs = pts[1] + [p[1] for cb in self.p.get("cables", []) for p in cb["path"] if cb["to"] != "offsite"] + [self.pad[2] - 14]
        x0, x1, z0, z1 = min(xs) - 10, max(xs) + 10, min(zs) - 6, max(zs) + 10
        s, m = 14.0, 50
        W, H = int((x1 - x0) * s) + 2 * m, int((z1 - z0) * s) + 2 * m + 60
        img = Image.new("RGB", (W, H), (18, 22, 26))
        d = ImageDraw.Draw(img)
        P = lambda x, z: (m + (x - x0) * s, 60 + m + (z1 - z) * s)
        edge = self.p["site"].get("ledge_edge_z")
        if edge is not None:
            d.rectangle([P(x0, edge), P(x1, z0)], fill=(6, 8, 12))
            d.line([P(x0, edge), P(x1, edge)], fill=(90, 110, 120), width=3)
            d.text((P(x0, edge)[0] + 6, P(x0, edge)[1] + 6), "LEDGE EDGE · the chasm", fill=(90, 110, 120), font=font(16, True))
        px0, px1, pz0, pz1 = self.pad
        d.rectangle([P(px0, pz1), P(px1, pz0)], outline=(80, 100, 90), width=2)
        d.text((P(px0, pz1)[0] + 6, P(px0, pz1)[1] + 6), "flat pad", fill=(110, 140, 120), font=font(14))
        d.text((P(x0, z0)[0] + 6, P(x0, z0)[1] - 26), "FRONT (-z)", fill=(110, 140, 120), font=font(14, True))
        ap = self.p.get("approach")
        if ap:
            half = self.c.get("approach_width_m", 8.0) / 2
            (ax, az), (bx, bz) = ap["from"], ap["to"]
            d.rectangle([P(min(ax, bx) - half, max(az, bz)), P(max(ax, bx) + half, max(min(az, bz), z0))], fill=(26, 40, 48))
            d.text((P(ax + half + 1, z0 + 4)), "sub's approach", fill=(120, 160, 180), font=font(14))
        for cb in self.p.get("cables", []):
            path = [P(*p) for p in cb["path"]]
            d.line(path, fill=(200, 140, 60), width=2)
            if "break_at" in cb:
                bx, by = P(*cb["break_at"])
                d.line([(bx - 8, by - 8), (bx + 8, by + 8)], fill=(240, 70, 60), width=3)
                d.line([(bx - 8, by + 8), (bx + 8, by - 8)], fill=(240, 70, 60), width=3)
        hb = self.hover_box()
        d.rectangle([P(hb[0], hb[3]), P(hb[1], hb[2])], outline=(240, 140, 40), width=3)
        d.text((P(hb[0], hb[2])[0], P(hb[0], hb[2])[1] + 4), f"sub hovering (keel {self.keel_y:.1f} m)", fill=(240, 140, 40), font=font(14))
        for e in sorted(self.els.values(), key=lambda e: e.top):
            col = ROLE_COL.get(e.role, (140, 140, 140))
            if e.kind == "cyl":
                cx, cy = P(*e.at)
                r = max(3, e.r * s)
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col, outline=(30, 30, 30))
            else:
                bx0, bx1, bz0, bz1 = e.box
                d.rectangle([P(bx0, bz1), P(bx1, bz0)], fill=col, outline=(30, 30, 30), width=2)
            if e.role in ("node", "post"):
                cx, cy = P(*e.centre())
                d.text((cx + 12, cy - 22 if e.role == "post" else cy - 8), e.id, fill=(230, 232, 235), font=font(14, True))
        for sp in self.p.get("service_points", []):
            px, py = P(*sp["at"])
            fx, fz = FACES[sp["faces"]]
            tip = (px + fx * 14, py - fz * 14)
            d.polygon([tip, (px - fz * 6, py - fx * 6), (px + fz * 6, py + fx * 6)], fill=(245, 200, 90))
        d.text((m, 14), f"{self.p.get('name', 'site')} · plan (amber: cables, red X: the cable break, yellow: service points)",
               fill=(240, 180, 90), font=font(22, True))
        d.line([(m, H - 24), (m + 10 * s, H - 24)], fill=(200, 205, 210), width=3)
        d.text((m + 10 * s + 8, H - 33), "10 m", fill=(200, 205, 210), font=font(14))
        img.save(out)

    def draw_elevation(self, out: Path) -> None:
        xs = [v for e in self.els.values() for v in e.bounds()[0:2]]
        x0, x1 = min(xs) - 8, max(xs) + 8
        ytop = max(e.top for e in self.els.values()) + 4
        y0 = -12
        s, m = 14.0, 50
        W, H = int((x1 - x0) * s) + 2 * m, int((ytop - y0) * s) + 2 * m + 40
        img = Image.new("RGB", (W, H), (18, 22, 26))
        d = ImageDraw.Draw(img)
        P = lambda x, y: (m + (x - x0) * s, 40 + m + (ytop - y) * s)
        d.rectangle([P(x0, 0), P(x1, y0)], fill=(40, 46, 44))
        for e in sorted(self.els.values(), key=lambda e: -e.bounds()[2]):
            col = ROLE_COL.get(e.role, (140, 140, 140))
            bx0, bx1, _, _ = e.bounds()
            d.rectangle([P(bx0, e.top), P(bx1, e.base)], fill=col, outline=(30, 30, 30))
        hb = self.hover_box()
        sub = self.p["site"]["sub"]
        d.rounded_rectangle([P(hb[0], self.keel_y + sub["height_m"]), P(hb[1], self.keel_y)], radius=10, outline=(240, 140, 40), width=3)
        d.text((m, 10), f"{self.p.get('name', 'site')} · elevation from the front", fill=(240, 180, 90), font=font(22, True))
        img.save(out)

    def export(self, out: Path) -> None:
        sub = self.p["site"]["sub"]
        data = {"kind": "site", "site": self.p["site"], "elements": self.p["elements"], "cables": self.p.get("cables", []),
                "service_points": self.p.get("service_points", []), "sub_hover": {**self.p["sub_hover"], "keel_y": self.keel_y},
                "sub": sub, "cameras": self.p.get("cameras", [])}
        out.write_text(json.dumps(data, indent=1), encoding="utf-8")


def main() -> int:
    prog = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else prog.parent / "renders"
    out.mkdir(parents=True, exist_ok=True)
    site = Site(yaml.safe_load(prog.read_text(encoding="utf-8")) | {"name": prog.parent.name})
    swims = site.run()
    site.draw_plan(out / "site_plan.png")
    site.draw_elevation(out / "site_elevation.png")
    site.export(out / "layout.json")
    failed = [m for ok, m in site.results if not ok]
    lines = [f"{'ok  ' if ok else 'FAIL'} {m}" for ok, m in site.results] + ["", "# swims"] + swims + ["", f"{len(failed)} problem(s)"]
    (out / "report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join([l for l in lines if l.startswith("FAIL")] + lines[-1:]))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
