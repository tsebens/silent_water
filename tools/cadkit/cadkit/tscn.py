"""A small writer for Godot 4 text scenes (.tscn): build scripts generate scenes, nobody hand-edits them.

Positions are metres. `Xform` carries a 3x3 basis given as columns (X, Y, Z axes) and an origin; Godot writes the
basis row by row, which `fmt` handles.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class Res:
    kind: str   # "Ext" or "Sub"
    id: str


@dataclass(frozen=True)
class NodePath:
    path: str


@dataclass(frozen=True)
class SName:
    name: str


@dataclass
class Xform:
    basis: np.ndarray = field(default_factory=lambda: np.eye(3))   # columns are the local X, Y, Z axes
    origin: tuple[float, float, float] = (0.0, 0.0, 0.0)

    @staticmethod
    def frame(x_axis, y_axis, z_axis, origin=(0.0, 0.0, 0.0)) -> "Xform":
        return Xform(np.column_stack([np.asarray(x_axis, float), np.asarray(y_axis, float), np.asarray(z_axis, float)]),
                     tuple(float(c) for c in origin))

    def __matmul__(self, other: "Xform") -> "Xform":
        o = self.basis @ np.asarray(other.origin) + np.asarray(self.origin)
        return Xform(self.basis @ other.basis, tuple(float(c) for c in o))

    def apply(self, p) -> np.ndarray:
        return self.basis @ np.asarray(p, float) + np.asarray(self.origin)


def rot_y(deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        r = f"{float(v):.6g}"
        return "0" if r == "-0" else r
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, Res):
        return f'{v.kind}Resource("{v.id}")'
    if isinstance(v, NodePath):
        return f'NodePath("{v.path}")'
    if isinstance(v, SName):
        return f'&"{v.name}"'
    if isinstance(v, Xform):
        b = v.basis
        nums = [b[r][c] for r in range(3) for c in range(3)] + list(v.origin)
        return "Transform3D(" + ", ".join(fmt(float(n)) for n in nums) + ")"
    if isinstance(v, (list, tuple)) and v and all(isinstance(x, str) for x in v):
        return "PackedStringArray(" + ", ".join(fmt(x) for x in v) + ")"
    if isinstance(v, (list, tuple)) and len(v) == 3:
        return "Vector3(" + ", ".join(fmt(float(x)) for x in v) + ")"
    raise TypeError(f"cannot write {v!r}")


class Scene:
    """Nodes are kept as specs and written at the end, so properties can be set after resources are made."""

    def __init__(self, root: str, type_: str | None = "Node3D", script: str | None = None, instance: str | None = None,
                 props: dict | None = None):
        self._ext: dict[str, tuple[str, str]] = {}
        self._sub: list[tuple[str, str, dict]] = []
        self._nodes: list[dict] = []
        self.root = root
        self.node(root, parent=None, type_=type_, script=script, instance=instance, props=props)

    def ext(self, type_: str, path: str) -> Res:
        if path not in self._ext:
            self._ext[path] = (type_, str(len(self._ext) + 1))
        return Res("Ext", self._ext[path][1])

    def sub(self, type_: str, id_: str, props: dict) -> Res:
        self._sub.append((type_, id_, props))
        return Res("Sub", id_)

    def node(self, name: str, parent: str | None = ".", type_: str | None = "Node3D", script: str | None = None,
             instance: str | None = None, props: dict | None = None) -> str:
        path = "." if parent is None else (name if parent == "." else f"{parent}/{name}")
        self._nodes.append({"name": name, "parent": parent, "type": type_, "script": script, "instance": instance,
                            "props": dict(props or {}), "path": path})
        if instance is not None:
            self.ext("PackedScene", instance)
        if script is not None:
            self.ext("Script", script)
        return path

    def set(self, path: str, **props) -> None:
        for n in self._nodes:
            if n["path"] == path:
                n["props"].update(props)
                return
        raise KeyError(path)

    def _node_text(self, n: dict) -> str:
        head = f'[node name="{n["name"]}"'
        if n["instance"] is None and n["type"] is not None:
            head += f' type="{n["type"]}"'
        if n["parent"] is not None:
            head += f' parent="{n["parent"]}"'
        paths = [k for k, v in n["props"].items() if isinstance(v, NodePath)]
        if paths:
            head += " node_paths=" + fmt(paths)
        if n["instance"] is not None:
            head += f" instance={fmt(self.ext('PackedScene', n['instance']))}"
        lines = [head + "]"]
        if n["script"] is not None:
            lines.append(f"script = {fmt(self.ext('Script', n['script']))}")
        lines += [f"{k} = {fmt(v)}" for k, v in n["props"].items()]
        return "\n".join(lines)

    def text(self) -> str:
        out = ["[gd_scene format=3]", ""]
        for path, (type_, id_) in self._ext.items():
            out.append(f'[ext_resource type="{type_}" path="{path}" id="{id_}"]')
        if self._ext:
            out.append("")
        for type_, id_, props in self._sub:
            out.append(f'[sub_resource type="{type_}" id="{id_}"]')
            out += [f"{k} = {fmt(v)}" for k, v in props.items()]
            out.append("")
        for n in self._nodes:
            out += [self._node_text(n), ""]
        return "\n".join(out).rstrip() + "\n"

    def write(self, path: Path) -> None:
        from cadkit import library
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.text())
        library.note(path)


def grab_box(scene: Scene, parent: str, size_m: tuple[float, float, float], centre_m: tuple[float, float, float],
             id_: str = "grab") -> None:
    """The standard grab collider: a StaticBody3D on collision layer 2 with one box shape."""
    shape = scene.sub("BoxShape3D", id_, {"size": tuple(size_m)})
    body = scene.node("Grab", parent=parent, type_="StaticBody3D", props={"collision_layer": 2, "collision_mask": 0})
    scene.node("Shape", parent=body, type_="CollisionShape3D",
               props={"transform": Xform(origin=centre_m), "shape": shape})
