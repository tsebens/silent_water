"""Minimal 'kit CAD' helpers for the spike: build123d parts -> Onshape-shaped glTF (write a .glb: one file) the kit importer accepts.

Frame (glTF, metres): X right, Y up, Z out of the panel (front). The back face sits on Z=0, centred on the origin.
A moving part is modelled with its hinge on the local X axis through its origin, standing out along +Z (upright),
and placed with `hinge=(x, y, z)`; it arrives as `occurrence of <name>` -> `<name>`, like an Onshape export.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field

import numpy as np
import trimesh
from OCP.BRepTools import BRepTools
import build123d as bd

PALETTE = {  # assets/style_bible/kit_palette.yaml
    "powder_grey": (0.65, 0.65, 0.65),
    "safety_orange": (1.0, 0.40, 0.0),
    "black": (0.04, 0.04, 0.04),
    "led": (0.2, 0.7, 1.0),
}


@dataclass
class KitPart:
    name: str
    shape: bd.Part
    colour: str
    hinge: tuple[float, float, float] | None = None   # mm, in the kit frame; None = fixed part at the origin
    stats: dict = field(default_factory=dict)


def tessellate(shape: bd.Shape, tol_mm: float = 0.2, ang: float = 0.5) -> tuple[np.ndarray, np.ndarray]:
    BRepTools.Clean_s(shape.wrapped)  # drop any cached finer triangulation
    verts, tris = shape.tessellate(tolerance=tol_mm, angular_tolerance=ang)
    return np.array([[v.X, v.Y, v.Z] for v in verts]) / 1000.0, np.array(tris, dtype=np.int64)


def onshape_material_name(rgb: tuple[float, float, float]) -> str:
    return "_".join(f"{c:.6f}" for c in (*rgb, 0.0, 0.0))


def export_kit_gltf(parts: list[KitPart], path: str) -> dict:
    scene = trimesh.Scene()
    report = {}
    for p in parts:
        v, t = tessellate(p.shape)
        mesh = trimesh.Trimesh(v, t, process=False)
        rgb = PALETTE[p.colour]
        mesh.visual = trimesh.visual.TextureVisuals(
            material=trimesh.visual.material.PBRMaterial(
                name=onshape_material_name(rgb), baseColorFactor=[*rgb, 1.0], metallicFactor=0.0, roughnessFactor=0.8))
        occ = f"occurrence of {p.name}"
        tf = np.eye(4)
        if p.hinge is not None:
            tf[:3, 3] = np.array(p.hinge) / 1000.0
        scene.graph.update(frame_from=scene.graph.base_frame, frame_to=occ, matrix=tf)
        scene.add_geometry(mesh, node_name=p.name, geom_name=p.name, parent_node_name=occ)
        report[p.name] = {"triangles": int(len(t)), "faces": len(p.shape.faces()), "volume_cm3": round(p.shape.volume / 1000, 2),
                          "bbox_mm": [[round(c, 2) for c in p.shape.bounding_box().min], [round(c, 2) for c in p.shape.bounding_box().max]],
                          "solids": len(p.shape.solids()), "valid": p.shape.is_valid}
    scene.export(path)
    report["_total_triangles"] = sum(r["triangles"] for r in report.values() if isinstance(r, dict))
    return report


def ngon_prism(sides: int, radius_mm: float, height_mm: float, rotation_deg: float = 0.0) -> bd.Part:
    """A polygonal 'cylinder' along +Z from z=0: explicit segment count, so the game mesh stays low-poly."""
    with bd.BuildPart() as b:
        with bd.BuildSketch():
            bd.RegularPolygon(radius_mm, sides, rotation=rotation_deg)
        bd.extrude(amount=height_mm)
    return b.part


def expect_one_solid(p: KitPart, n: int = 1) -> None:
    got = len(p.shape.solids())
    if got != n or not p.shape.is_valid:
        raise AssertionError(f"{p.name}: expected {n} valid solid(s), got {got}, valid={p.shape.is_valid}")


def expect_bbox(p: KitPart, lo: tuple, hi: tuple, slack_mm: float = 0.01) -> None:
    b = p.shape.bounding_box()
    got = (tuple(round(c, 3) for c in b.min), tuple(round(c, 3) for c in b.max))
    if any(g < l - slack_mm for g, l in zip(got[0], lo)) or any(g > h + slack_mm for g, h in zip(got[1], hi)):
        raise AssertionError(f"{p.name}: bbox {got} outside expected {lo}..{hi}")


# --- scene-assembly spike (#345): solids only, one GLB per rigid set ---------------------------------------------
#
# A GLB holds every static solid of a scene that shares one frame. Colours are palette roles written as vertex
# colours (COLOR_0, linear), so one GLB can carry several colours; the shared post-import script turns them on.
# A moving part gets its own GLB, modelled in its own frame with the motion axis through the origin.

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
IMPORT_SCRIPT = "res://assets/import/vertex_color_import.gd"


@dataclass
class Solid:
    shape: bd.Shape          # mm, in the GLB's frame
    colour: str              # a PALETTE role


def srgb_to_linear(rgb: tuple[float, float, float]) -> tuple[float, ...]:
    """Palette values are picked as sRGB (as a colour picker shows them); glTF vertex colours are linear."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)


def expect_in_front(solids: list["Solid"], what: str) -> None:
    """A panel part must not reach behind its mount face (Z=0): the panel it sits on has no hole for it."""
    for s in solids:
        z0 = s.shape.bounding_box().min.Z
        expect(z0 >= -0.01, f"{what}: a {s.colour} solid reaches {z0:.1f} mm behind the mount face")


def solids_mesh(solids: list[Solid], tol_mm: float = 0.2, ang: float = 0.5) -> trimesh.Trimesh:
    """One flat-shaded triangle mesh in metres: every triangle has its own vertices, coloured by its solid's role."""
    parts = []
    for s in solids:
        if s.colour not in PALETTE:
            raise ValueError(f"colour {s.colour!r} is not a palette role: {sorted(PALETTE)}")
        v, t = tessellate(s.shape, tol_mm, ang)
        m = trimesh.Trimesh(v, t, process=False)
        m.unmerge_vertices()
        rgb = np.array([*srgb_to_linear(PALETTE[s.colour]), 1.0])
        m.visual = trimesh.visual.ColorVisuals(m, vertex_colors=np.tile((rgb * 255).round().astype(np.uint8), (len(m.vertices), 1)))
        parts.append(m)
    mesh = trimesh.util.concatenate(parts)
    _ = mesh.vertex_normals  # with unmerged vertices these are the face normals: flat shading
    return mesh


def export_solids_glb(solids: list[Solid], path: Path, node_name: str, tol_mm: float = 0.2, ang: float = 0.5) -> dict:
    """Write a GLB of the solids (one mesh node named `node_name`) and its Godot .import. Returns triangles and bbox."""
    mesh = solids_mesh(solids, tol_mm, ang)
    scene = trimesh.Scene()
    scene.add_geometry(mesh, node_name=node_name, geom_name=node_name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(scene.export(file_type="glb", include_normals=True))
    res = "res://" + path.resolve().relative_to(REPO).as_posix()
    imp = Path(str(path) + ".import")
    if not imp.exists():
        imp.write_text(f'[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\n\n'
                       f'source_file="{res}"\n\n[params]\n\nimport_script/path="{IMPORT_SCRIPT}"\n')
    lo, hi = mesh.bounds
    return {"glb": res, "triangles": int(len(mesh.faces)), "bbox_m": [lo.round(4).tolist(), hi.round(4).tolist()]}


def at(shape: bd.Shape, x: float = 0.0, y: float = 0.0, z: float = 0.0, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> bd.Shape:
    """Move a shape (mm, degrees about X, then Y, then Z)."""
    return shape.moved(bd.Location((x, y, z), (rx, ry, rz)))


def box(w: float, h: float, d: float, chamfer_mm: float = 0.0, base_z: bool = True) -> bd.Part:
    """A box w (X) by h (Y) by d (Z), centred in X and Y, from Z=0 to d (or centred in Z), edges chamfered."""
    b = bd.Box(w, h, d, align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN if base_z else bd.Align.CENTER))
    return bd.chamfer(b.edges(), chamfer_mm) if chamfer_mm > 0 else b


def prism(sides: int, radius: float, height: float, chamfer_top: float = 0.0, rotation_deg: float | None = None) -> bd.Part:
    """A polygonal cylinder along +Z from Z=0 with an explicit side count (low-poly by construction)."""
    p = ngon_prism(sides, radius, height, rotation_deg if rotation_deg is not None else 180.0 / sides)
    if chamfer_top > 0:
        p = bd.chamfer(p.faces().sort_by(bd.Axis.Z)[-1].edges(), chamfer_top)
    return p


class GeometryError(AssertionError):
    pass


def expect(cond: bool, what: str) -> None:
    """A geometric assertion against the brief. Every scene's build must pass all of them before it writes files."""
    if not cond:
        raise GeometryError(what)


def bbox_mm(shape: bd.Shape) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    b = shape.bounding_box()
    return (tuple(round(c, 2) for c in b.min), tuple(round(c, 2) for c in b.max))
