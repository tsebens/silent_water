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
