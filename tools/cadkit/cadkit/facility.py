"""Facility floorplan programs: read one, check it for play, draw it.

    cadkit plan <program.yaml> [out_dir]

Writes into out_dir (default: a `renders/` folder beside the program): `site.png` (the ground floor of every
structure, the tunnels and the ledge), one `plan_<view>.png` per plan view (the program's `plan_views`, else one per
level), `report.txt` (every check, then routes and objectives) and `layout.json` (rooms, doors and tunnels
resolved, for the greybox). `load(path)` returns the parsed `Plan` so a facility build script can read it.

The checks are for play first (design doc, "Facilities"): every door passes a suited diver; the carry route passes a
carried survivor; the station can be walked from the dock to the reactor with no power; doors between watertight
zones are watertight; levels have headroom; each level of a multi-room structure has a loop; rooms fit their
structure and don't overlap. Every failure names the part.
"""
from __future__ import annotations

import heapq
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageFont

TOL = 0.05                 # metres: a door counts as on a wall within this
EXTERNAL = {"sub", "sea"}  # door targets outside the station


@dataclass
class Room:
    id: str
    levels: list[str]
    rect: tuple[float, float, float, float]
    use: str
    structure: str
    zone: str
    corridor: bool = False
    bunks: int = 0
    tags: list[str] = field(default_factory=list)
    tunnel: bool = False
    path: list[tuple[float, float]] = field(default_factory=list)
    width: float = 0.0
    height: float = 0.0

    @property
    def area(self) -> float:
        x0, x1, z0, z1 = self.rect
        return (x1 - x0) * (z1 - z0)

    @property
    def centre(self) -> tuple[float, float]:
        x0, x1, z0, z1 = self.rect
        return ((x0 + x1) / 2, (z0 + z1) / 2)


@dataclass
class Door:
    a: str
    b: str
    at: tuple[float, float]
    width: float
    kind: str
    level: str | None = None


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/{name}", size)
    except OSError:
        return ImageFont.load_default()


def on_boundary(rect: tuple[float, float, float, float], p: tuple[float, float]) -> bool:
    x0, x1, z0, z1 = rect
    x, z = p
    inside_x = x0 - TOL <= x <= x1 + TOL
    inside_z = z0 - TOL <= z <= z1 + TOL
    return (inside_z and (abs(x - x0) <= TOL or abs(x - x1) <= TOL)) or \
           (inside_x and (abs(z - z0) <= TOL or abs(z - z1) <= TOL))


def inside(rect: tuple[float, float, float, float], p: tuple[float, float]) -> bool:
    x0, x1, z0, z1 = rect
    return x0 - TOL <= p[0] <= x1 + TOL and z0 - TOL <= p[1] <= z1 + TOL


def overlap(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    w = min(a[1], b[1]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[2], b[2])
    return w * h if w > TOL and h > TOL else 0.0


def path_length(path: list[tuple[float, float]]) -> float:
    return sum(math.dist(p, q) for p, q in zip(path, path[1:]))


class Plan:
    def __init__(self, program: dict) -> None:
        self.p = program
        self.clear = program.get("clearances", {})
        self.structures = {s["id"]: s for s in program["structures"]}
        self.level_of: dict[str, dict] = {}
        self.structure_of_level: dict[str, str] = {}
        for s in program["structures"]:
            for lv in s["levels"]:
                self.level_of[lv["id"]] = lv
                self.structure_of_level[lv["id"]] = s["id"]
        self.rooms: dict[str, Room] = {}
        for r in program["rooms"]:
            levels = r.get("levels") or [r["level"]]
            struct = self.structure_of_level[levels[0]]
            self.rooms[r["id"]] = Room(r["id"], levels, tuple(r["rect"]), r.get("use", r["id"]), struct,
                                       r.get("zone", struct), bool(r.get("corridor")), int(r.get("bunks", 0)),
                                       list(r.get("tags", [])))
        for t in program.get("tunnels", []):
            path = [tuple(p) for p in t["path"]]
            xs = [p[0] for p in path]
            zs = [p[1] for p in path]
            hw = t["width"] / 2
            self.rooms[t["id"]] = Room(t["id"], [], (min(xs) - hw, max(xs) + hw, min(zs) - hw, max(zs) + hw),
                                       t.get("use", t["id"]), "tunnel", t["id"], True, tags=list(t.get("tags", [])),
                                       tunnel=True, path=path, width=t["width"], height=t.get("height", 2.4))
        self.doors = [Door(d["between"][0], d["between"][1], tuple(d["at"]), float(d["width"]), d["kind"],
                           d.get("level")) for d in program["doors"]]
        self.results: list[tuple[bool, str]] = []

    # ---- checks ---------------------------------------------------------------------------------------------------

    def check(self, ok: bool, msg: str) -> None:
        self.results.append((ok, msg))

    def run_checks(self) -> None:
        c = self.clear
        for lid, lv in self.level_of.items():
            self.check(lv["height"] >= c.get("headroom_m", 2.4), f"headroom {lid}: {lv['height']:.1f} m")
        for t in (r for r in self.rooms.values() if r.tunnel):
            self.check(t.height >= c.get("headroom_m", 2.4), f"headroom {t.id}: {t.height:.1f} m")
        for r in self.rooms.values():
            if r.tunnel:
                continue
            srect = self.structures[r.structure]["rect"]
            self.check(all(inside(srect, (x, z)) for x in r.rect[:2] for z in r.rect[2:]),
                       f"{r.id} lies inside {r.structure}")
            if r.bunks:
                per = r.area / r.bunks
                self.check(per >= c.get("bunk_area_m2", 5.0), f"{r.id}: {per:.1f} m² per bunk ({r.bunks} bunks)")
        rooms = [r for r in self.rooms.values() if not r.tunnel]
        for i, a in enumerate(rooms):
            for b in rooms[i + 1:]:
                if set(a.levels) & set(b.levels):
                    ov = overlap(a.rect, b.rect)
                    if ov:
                        self.check(False, f"{a.id} overlaps {b.id} by {ov:.1f} m²")
        # the room tagged largest_room really is the largest in its structure
        for r in rooms:
            if "largest_room" in r.tags:
                peers = [q for q in rooms if q.structure == r.structure and not q.corridor and q is not r]
                big = max(peers, key=lambda q: q.area)
                self.check(r.area >= big.area, f"{r.id} ({r.area:.0f} m²) is the largest room in {r.structure} "
                                               f"(next: {big.id}, {big.area:.0f} m²)")
        for d in self.doors:
            for end in (d.a, d.b):
                if end in EXTERNAL:
                    continue
                if end not in self.rooms:
                    self.check(False, f"door {d.a}-{d.b}: no room {end!r}")
                    continue
                r = self.rooms[end]
                if r.tunnel:
                    ok = min(math.dist(d.at, r.path[0]), math.dist(d.at, r.path[-1])) <= TOL
                    self.check(ok, f"door {d.a}-{d.b} at {d.at} is at an end of {end}")
                elif d.kind == "hatch" and ({d.a, d.b} & EXTERNAL):
                    self.check(inside(r.rect, d.at), f"hatch {d.a}-{d.b} at {d.at} is in the floor of {end}")
                else:
                    self.check(on_boundary(r.rect, d.at), f"door {d.a}-{d.b} at {d.at} is on a wall of {end}")
            need = c.get("door_suited_m", 1.0) if not ({d.a, d.b} & EXTERNAL) else 0.8
            self.check(d.width >= need, f"door {d.a}-{d.b}: {d.width:.1f} m clear (suited diver needs {need:.1f})")
            za, zb = self.zone(d.a), self.zone(d.b)
            if za != zb:
                self.check(d.kind in ("watertight", "hatch"),
                           f"door {d.a}-{d.b} between zones {za} and {zb} is watertight ({d.kind})")
        # every room has at least one door
        touched = {e for d in self.doors for e in (d.a, d.b)}
        for r in self.rooms.values():
            self.check(r.id in touched, f"{r.id} has a door")
        # loops: on each level of a structure with several rooms, the room graph has a cycle
        for lid in self.level_of:
            nodes = {r.id for r in self.rooms.values() if lid in r.levels}
            if len(nodes) < 4:
                continue
            edges = {frozenset((d.a, d.b)) for d in self.doors if d.a in nodes and d.b in nodes and (d.level in (None, lid))}
            comps = self._components(nodes, edges)
            cyc = len(edges) - len(nodes) + comps
            self.check(cyc >= 1, f"level {lid}: {cyc} independent loop(s), {comps} connected part(s)")
            self.check(comps == 1, f"level {lid} is one connected part")

    def zone(self, rid: str) -> str:
        return "outside" if rid in EXTERNAL else self.rooms[rid].zone

    @staticmethod
    def _components(nodes: set[str], edges: set[frozenset]) -> int:
        adj: dict[str, set[str]] = {n: set() for n in nodes}
        for e in edges:
            a, b = tuple(e)
            adj[a].add(b)
            adj[b].add(a)
        seen: set[str] = set()
        n = 0
        for s in nodes:
            if s in seen:
                continue
            n += 1
            stack = [s]
            while stack:
                u = stack.pop()
                if u in seen:
                    continue
                seen.add(u)
                stack.extend(adj[u] - seen)
        return n

    # ---- routes ---------------------------------------------------------------------------------------------------

    def route(self, start: str, goal: str, unpowered: bool = False, carry: bool = False) -> tuple[float, list[str]] | None:
        """Shortest walk between two rooms through door points. Inside a room the walk is straight from door to door;
        a tunnel adds its length. The start and goal are the room centres (external ends are their door)."""
        c = self.clear
        usable = []
        for i, d in enumerate(self.doors):
            if unpowered and d.kind == "powered":
                continue
            # a hatch is vertical and tight by nature: exempt from the carry width (it must still pass a diver)
            if carry and d.kind != "hatch" and (d.width < c.get("door_carry_m", 1.2) - TOL):
                continue
            usable.append(i)
        if carry:
            narrow = {r.id for r in self.rooms.values() if r.corridor and
                      min(r.rect[1] - r.rect[0], r.rect[3] - r.rect[2]) < c.get("corridor_carry_m", 1.6) - TOL}
        else:
            narrow = set()
        # nodes: ("room", id) for start/goal centres, ("door", i)
        def pos(node: tuple[str, object]) -> tuple[float, float]:
            if node[0] == "door":
                return self.doors[node[1]].at
            rid = node[1]
            return self.rooms[rid].centre if rid not in EXTERNAL else (0.0, 0.0)

        def doors_of(rid: str) -> list[int]:
            return [i for i in usable if rid in (self.doors[i].a, self.doors[i].b)]

        def hop(rid: str, p: tuple[float, float], q: tuple[float, float]) -> float:
            r = self.rooms.get(rid)
            if r is not None and r.tunnel:
                return path_length(r.path)
            return math.dist(p, q)

        startn = ("room", start)
        dist = {startn: 0.0}
        prev: dict = {}
        heap = [(0.0, 0, startn)]
        k = 1
        goaln = ("room", goal)
        while heap:
            du, _, u = heapq.heappop(heap)
            if u == goaln:
                break
            if du > dist.get(u, math.inf):
                continue
            if u[0] == "room":
                rid = u[1]
                nxt = []
                for i in doors_of(rid):
                    w = 0.0 if rid in EXTERNAL else hop(rid, self.rooms[rid].centre, self.doors[i].at) * (0.5 if self.rooms[rid].tunnel else 1)
                    nxt.append((("door", i), w))
            else:
                d = self.doors[u[1]]
                nxt = []
                for rid in (d.a, d.b):
                    if rid in narrow:
                        continue
                    if rid == goal:
                        w = 0.0 if rid in EXTERNAL else hop(rid, d.at, self.rooms[rid].centre) * (0.5 if self.rooms[rid].tunnel else 1)
                        nxt.append((goaln, w))
                    if rid in EXTERNAL:
                        continue
                    for j in doors_of(rid):
                        if j != u[1]:
                            nxt.append((("door", j), hop(rid, d.at, self.doors[j].at)))
            for v, w in nxt:
                nd = du + w
                if nd < dist.get(v, math.inf):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(heap, (nd, k, v))
                    k += 1
        if goaln not in dist:
            return None
        seq = []
        n = goaln
        while n in prev:
            seq.append(n)
            n = prev[n]
        seq.append(startn)
        rooms_on: list[str] = [start]
        for node in reversed(seq[:-1]):
            if node[0] == "door":
                d = self.doors[node[1]]
                other = d.b if rooms_on[-1] == d.a else d.a
                rooms_on.append(other)
        if rooms_on[-1] != goal:
            rooms_on.append(goal)
        return dist[goaln], rooms_on

    def blockers(self, rt: dict) -> str:
        """Name the parts that stop a route: relax one restriction at a time and list what it was."""
        c = self.clear
        unpowered, carry = bool(rt.get("unpowered")), bool(rt.get("carry"))
        names: list[str] = []
        if unpowered and self.route(rt["from"], rt["to"], False, carry) is not None:
            names += [f"powered door {d.a}-{d.b}" for d in self.doors if d.kind == "powered"]
        if carry and self.route(rt["from"], rt["to"], unpowered, False) is not None:
            names += [f"door {d.a}-{d.b} ({d.width:.1f} m)" for d in self.doors
                      if d.kind != "hatch" and d.width < c.get("door_carry_m", 1.2) - TOL]
            names += [f"corridor {r.id} ({min(r.rect[1] - r.rect[0], r.rect[3] - r.rect[2]):.1f} m)"
                      for r in self.rooms.values() if r.corridor and
                      min(r.rect[1] - r.rect[0], r.rect[3] - r.rect[2]) < c.get("corridor_carry_m", 1.6) - TOL]
        return f" (blocked by: {', '.join(names)})" if names else ""

    def run_routes(self) -> list[str]:
        lines = []
        for rt in self.p.get("routes", []):
            res = self.route(rt["from"], rt["to"], bool(rt.get("unpowered")), bool(rt.get("carry")))
            label = rt["id"] + (" (no power)" if rt.get("unpowered") else "") + (" (carrying)" if rt.get("carry") else "")
            if res is None:
                self.check(False, f"route {label}: no way from {rt['from']} to {rt['to']}" + self.blockers(rt))
                lines.append(f"{label}: NONE")
            else:
                d, rooms = res
                if rt.get("unpowered") or rt.get("carry"):
                    self.check(True, f"route {label}: {d:.0f} m")
                lines.append(f"{label}: {d:.0f} m  " + " > ".join(rooms))
        # what is out of reach without power
        dark = [r.id for r in self.rooms.values() if self.route("sub", r.id, unpowered=True) is None]
        lines.append("unreachable without power: " + (", ".join(dark) if dark else "none"))
        return lines

    # ---- drawing --------------------------------------------------------------------------------------------------

    DOOR_COL = {"open": None, "manual": (235, 235, 235), "powered": (240, 170, 60), "watertight": (220, 70, 60),
                "hatch": (120, 200, 255)}

    def draw(self, rects_for: list[Room], tunnels: list[Room], doors: list[Door], bounds: tuple[float, float, float, float],
             title: str, out: Path, scale: float, show_edge: bool = True, routes: list[tuple[list[str], tuple]] = ()) -> None:
        x0, x1, z0, z1 = bounds
        m = 60
        W, H = max(int((x1 - x0) * scale) + 2 * m, 760), int((z1 - z0) * scale) + 2 * m + 50
        img = Image.new("RGB", (W, H), (18, 22, 26))
        d = ImageDraw.Draw(img)

        def P(x: float, z: float) -> tuple[float, float]:
            return (m + (x - x0) * scale, 50 + m + (z1 - z) * scale)  # z inland points up the page; the chasm at the bottom

        if show_edge:
            ez = self.p.get("site", {}).get("ledge_edge_z", 0.0)
            if ez > z0:
                d.rectangle([P(x0, ez), P(x1, z0)], fill=(6, 8, 12))
                d.line([P(x0, ez), P(x1, ez)], fill=(90, 110, 120), width=3)
                d.text((P(x0, ez)[0] + 6, P(x0, ez)[1] + 6), "LEDGE EDGE · the chasm", fill=(90, 110, 120), font=font(16, True))
        for t in tunnels:
            pts = [P(*p) for p in t.path]
            d.line(pts, fill=(70, 80, 90), width=max(3, int(t.width * scale)))
            mid = pts[len(pts) // 2] if len(pts) > 2 else ((pts[0][0] + pts[-1][0]) / 2, (pts[0][1] + pts[-1][1]) / 2)
            d.text((mid[0] + 8, mid[1] - 8), f"{t.id} ({path_length(t.path):.0f} m)", fill=(170, 180, 190), font=font(14))
        for r in rects_for:
            a, b = P(r.rect[0], r.rect[3]), P(r.rect[1], r.rect[2])
            fill = (44, 50, 56) if r.corridor else (64, 72, 80)
            if r.zone != r.structure:
                fill = (70, 60, 62)
            d.rectangle([a, b], fill=fill, outline=(150, 160, 168), width=2)
            if (b[0] - a[0]) > 40 and (b[1] - a[1]) > 22:
                f = font(max(10, min(16, int(scale * 0.55))))
                label = "" if r.use == "Corridor" else r.use
                if len(r.levels) > 1:
                    label += " ↕ " + ", ".join(r.levels)
                words, lines, line = label.split(), [], ""
                for w in words:
                    if d.textlength((line + " " + w).strip(), font=f) > (b[0] - a[0]) - 8:
                        lines.append(line.strip())
                        line = ""
                    line += " " + w
                lines.append(line.strip())
                y = a[1] + 4
                for ln in lines:
                    if y + 16 < b[1]:
                        d.text((a[0] + 4, y), ln, fill=(230, 232, 235), font=f)
                    y += f.size + 2
                tags = [t.replace("objective_", "★ ") for t in r.tags if t.startswith("objective_")]
                if tags and y + 16 < b[1]:
                    d.text((a[0] + 4, y + 2), ", ".join(tags), fill=(245, 200, 90), font=font(12))
        for path, col in routes:
            pts = [P(*p) for p in path]
            for p, q in zip(pts, pts[1:]):
                d.line([p, q], fill=col, width=3)
        for dr in doors:
            col = self.DOOR_COL.get(dr.kind)
            cx, cy = P(*dr.at)
            h = dr.width * scale / 2
            t = max(3, scale * 0.25)
            if dr.kind == "hatch":
                d.ellipse([cx - h, cy - h, cx + h, cy + h], outline=col, width=3)
                continue
            along_x = self.wall_runs_x(dr)
            box = [cx - h, cy - t, cx + h, cy + t] if along_x else [cx - t, cy - h, cx + t, cy + h]
            if col is None:  # an opening: a gap in the wall
                d.rectangle(box, fill=(44, 50, 56))
            else:
                d.rectangle(box, fill=col)
        d.text((m, 14), title, fill=(240, 180, 90), font=font(24, True))
        for k, (name, col) in enumerate([("manual door", (235, 235, 235)), ("powered door (dead without power)", (240, 170, 60)),
                                         ("watertight door", (220, 70, 60)), ("hatch", (120, 200, 255))]):
            lx = m + [0, 130, 390, 540][k]
            d.rectangle([lx, 52, lx + 14, 66], fill=col)
            d.text((lx + 20, 50), name, fill=(200, 205, 210), font=font(13))
        # scale bar: 10 m
        bx, by = m, H - 24
        d.line([(bx, by), (bx + 10 * scale, by)], fill=(200, 205, 210), width=3)
        d.text((bx + 10 * scale + 8, by - 9), "10 m", fill=(200, 205, 210), font=font(14))
        img.save(out)

    def wall_runs_x(self, dr: Door) -> bool:
        """True when the door's wall runs along x (a door in a wall of constant z)."""
        for end in (dr.a, dr.b):
            r = self.rooms.get(end)
            if r is None:
                continue
            if r.tunnel:
                (ax, az), (bx, bz) = (r.path[0], r.path[1]) if math.dist(dr.at, r.path[0]) <= TOL else (r.path[-1], r.path[-2])
                return abs(bx - ax) < abs(bz - az)  # a door across a tunnel's end lies across the tunnel
            x0, x1, z0, z1 = r.rect
            if abs(dr.at[1] - z0) <= TOL or abs(dr.at[1] - z1) <= TOL:
                return True
            if abs(dr.at[0] - x0) <= TOL or abs(dr.at[0] - x1) <= TOL:
                return False
        return True

    def route_points(self, rooms: list[str]) -> list[tuple[float, float]]:
        pts = []
        for a, b in zip(rooms, rooms[1:]):
            for d in self.doors:
                if {d.a, d.b} == {a, b}:
                    r = self.rooms.get(a)
                    if r is not None and r.tunnel and pts:
                        pts.extend(r.path if math.dist(r.path[0], pts[-1]) < math.dist(r.path[-1], pts[-1]) else r.path[::-1])
                    pts.append(d.at)
                    break
        return pts

    def export(self, path: Path) -> None:
        data = {
            "structures": self.p["structures"],
            "rooms": [{"id": r.id, "levels": r.levels, "rect": r.rect, "use": r.use, "structure": r.structure,
                       "zone": r.zone, "corridor": r.corridor, "tags": r.tags,
                       "floor_y": [self.level_of[l]["floor_y"] for l in r.levels],
                       "height": [self.level_of[l]["height"] for l in r.levels]}
                      for r in self.rooms.values() if not r.tunnel],
            "tunnels": [{"id": r.id, "path": r.path, "width": r.width, "height": r.height, "length": path_length(r.path)}
                        for r in self.rooms.values() if r.tunnel],
            "doors": [{"between": [d.a, d.b], "at": d.at, "width": d.width, "kind": d.kind, "level": d.level}
                      for d in self.doors],
        }
        path.write_text(json.dumps(data, indent=1), encoding="utf-8")




def load(path: Path | str) -> Plan:
    """Read a program.yaml into a Plan (nothing is checked or drawn)."""
    return Plan(yaml.safe_load(Path(path).read_text(encoding="utf-8")))


def check(plan: Plan) -> tuple[list[str], list[str]]:
    """Run every check and the routes. Returns (failure messages, report lines)."""
    plan.results = []
    plan.run_checks()
    route_lines = plan.run_routes()
    failed = [m for ok, m in plan.results if not ok]
    lines = [f"{'ok  ' if ok else 'FAIL'} {m}" for ok, m in plan.results]
    lines += ["", "# routes (walking distance through door points)"] + route_lines
    lines += ["", "# objectives"]
    for r in plan.rooms.values():
        for t in r.tags:
            if t.startswith("objective_"):
                res = plan.route("sub", r.id)
                lines.append(f"{t[10:]}: {r.id} ({r.use}), {res[0]:.0f} m from the sub" if res else f"{t}: {r.id} unreachable")
    lines += ["", f"{len(failed)} problem(s)"]
    return failed, lines


def draw_all(plan: Plan, title: str, out: Path) -> None:
    """The site image and one plan image per view, plus layout.json, into out."""
    out.mkdir(parents=True, exist_ok=True)
    allx = [v for s in plan.structures.values() for v in s["rect"][:2]] + [p[0] for r in plan.rooms.values() if r.tunnel for p in r.path]
    allz = [v for s in plan.structures.values() for v in s["rect"][2:]] + [p[1] for r in plan.rooms.values() if r.tunnel for p in r.path]
    pad = 8
    bounds = (min(allx) - pad, max(allx) + pad, min(allz) - pad, max(allz) + pad)
    ground = {s["levels"][0]["id"] for s in plan.structures.values()}
    struct_rooms = [r for r in plan.rooms.values() if not r.tunnel and r.levels[0] in ground]
    dark_to = next((r["to"] for r in plan.p.get("routes", []) if r.get("unpowered")), None)
    dark = plan.route("sub", dark_to, unpowered=True) if dark_to else None
    routes = [(plan.route_points(dark[1]), (255, 90, 90))] if dark else []
    plan.draw(struct_rooms, [r for r in plan.rooms.values() if r.tunnel], [d for d in plan.doors if "sub" in (d.a, d.b) or "sea" in (d.a, d.b)],
              bounds, f"{title} · site (red: the walk to the reactor, no power)", out / "site.png", 9.0, routes=routes)
    views = plan.p.get("plan_views") or [{"id": lid, "levels": [lid]} for lid in plan.level_of]
    for v in views:
        lids = v["levels"]
        rooms = [r for r in plan.rooms.values() if set(lids) & set(r.levels)]
        ids = {r.id for r in rooms}
        doors = [d for d in plan.doors if (d.a in ids or d.b in ids) and d.level in (None, *lids)]
        rects = [plan.structures[plan.structure_of_level[l]]["rect"] for l in lids]
        b = (min(r[0] for r in rects) - 4, max(r[1] for r in rects) + 4, min(r[2] for r in rects) - 4, max(r[3] for r in rects) + 4)
        names = " + ".join(f"{plan.structures[plan.structure_of_level[l]].get('name', l)} · {plan.level_of[l].get('name', l)} ({l})" for l in lids)
        floor = plan.level_of[lids[0]]["floor_y"]
        plan.draw(rooms, [], doors, b, v.get("title", f"{names}, floor at {floor:.1f} m"), out / f"plan_{v['id']}.png", 32.0)
    plan.export(out / "layout.json")


def run(program: Path | str, out: Path | str | None = None) -> tuple[list[str], list[str], Path]:
    """Check and draw a program. Returns (failures, report lines, out dir); writes the images and report.txt."""
    prog_path = Path(program).resolve()
    out_dir = Path(out).resolve() if out else prog_path.parent / "renders"
    plan = load(prog_path)
    failed, lines = check(plan)
    draw_all(plan, prog_path.parent.name, out_dir)
    (out_dir / "report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return failed, lines, out_dir


def summary(failed: list[str], lines: list[str]) -> str:
    return "\n".join([f"FAIL {m}" for m in failed] + lines[-1:])
