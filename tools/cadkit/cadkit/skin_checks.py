"""Build-time checks for skinned scenes, in the spirit of `solids.expect`: each raises `GeometryError` naming what is wrong.

The array checks take vertices in millimetres, `joints` (n, 4) and `weights` (n, 4) as written to a GLB, and a
`Skeleton`. `check_skinned_glb` reads a written file back and runs them all against what is actually in it.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

from cadkit.skeleton import Bone, Skeleton
from cadkit.solids import expect, read_skinned

WEIGHT_TOL = 1e-3
MAX_BONES = 64


def expect_weighted(joints: np.ndarray, weights: np.ndarray, n_bones: int, what: str, tol: float = WEIGHT_TOL) -> None:
    """Every vertex is weighted (not all zero), weights are non-negative and sum to 1, and every influence names a bone."""
    expect(joints.shape == weights.shape and joints.ndim == 2, f"{what}: joints {joints.shape} and weights {weights.shape} differ")
    expect(bool((weights >= -tol).all()), f"{what}: a vertex has a negative weight")
    total = weights.sum(axis=1)
    bare = int((total <= tol).sum())
    expect(bare == 0, f"{what}: {bare} vertices are unweighted")
    off = int((np.abs(total - 1.0) > tol).sum())
    expect(off == 0, f"{what}: {off} vertices have weights not summing to 1 (worst {np.abs(total - 1).max():.4f})")
    used = joints[weights > tol]
    expect(used.size == 0 or int(used.max()) < n_bones, f"{what}: a vertex is bound to bone {int(used.max())}, "
           f"but there are {n_bones} bones")


def expect_bone_count(skel: Skeleton, what: str, limit: int = MAX_BONES) -> None:
    expect(len(skel.bones) <= limit, f"{what}: {len(skel.bones)} bones, over the limit of {limit}")


def _segment_distance(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ab = b - a
    denom = float(ab @ ab)
    t = np.zeros(len(p)) if denom < 1e-12 else np.clip(((p - a) @ ab) / denom, 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def expect_no_far_binding(skel: Skeleton, pos_mm: np.ndarray, joints: np.ndarray, weights: np.ndarray, what: str,
                          max_mm: float, tol: float = WEIGHT_TOL) -> None:
    """No vertex with real weight on a bone lies more than `max_mm` from that bone's head-to-tail segment."""
    worst, where = 0.0, ""
    for j in np.unique(joints[weights > tol]):
        b = skel.bones[int(j)]
        m = ((joints == j) & (weights > tol)).any(axis=1)
        d = _segment_distance(pos_mm[m], np.array(b.head, dtype=float), np.array(b.tail, dtype=float)).max()
        if d > worst:
            worst, where = float(d), b.name
    expect(worst <= max_mm, f"{what}: a vertex is bound to {where!r} but lies {worst:.1f} mm from it (limit {max_mm:.1f})")


def expect_rest_matches(static_mm: np.ndarray, rest_mm: np.ndarray, what: str, tol_mm: float = 0.01) -> None:
    """The skinned mesh at rest is the static mesh."""
    expect(static_mm.shape == rest_mm.shape, f"{what}: skinned mesh has {len(rest_mm)} vertices, static has {len(static_mm)}")
    err = float(np.abs(static_mm - rest_mm).max()) if len(static_mm) else 0.0
    expect(err <= tol_mm, f"{what}: the skinned mesh at rest differs from the static mesh by {err:.3f} mm (limit {tol_mm})")


def skeleton_of(bones: list[dict]) -> Skeleton:
    """A Skeleton from `read_skinned` bones (heads in metres). A bone's tail is its first child's head, else its own."""
    first_child: dict[str, np.ndarray] = {}
    for b in bones:
        if b["parent"] and b["parent"] not in first_child:
            first_child[b["parent"]] = b["head"]
    return Skeleton([Bone(b["name"], tuple(b["head"] * 1000.0), tuple(first_child.get(b["name"], b["head"]) * 1000.0),
                          b["parent"]) for b in bones])


def rest_positions_mm(bones: list[dict], pos_m: np.ndarray, joints: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """Where the file's own joint nodes and inverse bind matrices put the vertices at rest (mm). For a consistent rig
    each bone's world translation plus its inverse bind translation is zero, so nothing moves."""
    shift = np.array([b["head"] + b["ibm_t"] for b in bones])
    return (pos_m + (weights[:, :, None] * shift[joints]).sum(axis=1)) * 1000.0


def check_skinned_glb(path: Path, what: str, max_bones: int = MAX_BONES, max_bind_mm: float = 120.0,
                      static_mm: np.ndarray | None = None) -> Skeleton:
    """Read a skinned GLB back and run every check on it. `static_mm` (n, 3), if given, is the static mesh (all
    surfaces, in file order) the rest pose must match; otherwise it is the file's own vertices, which still catches
    inverse bind matrices that disagree with the joint nodes."""
    data = read_skinned(path)
    skel = skeleton_of(data["bones"])
    expect_bone_count(skel, what, max_bones)
    pos = np.concatenate([s["pos"] for s in data["surfaces"]])
    joints = np.concatenate([s["joints"] for s in data["surfaces"]]).astype(int)
    weights = np.concatenate([s["weights"] for s in data["surfaces"]]).astype(float)
    expect_weighted(joints, weights, len(skel.bones), what)
    expect_no_far_binding(skel, pos * 1000.0, joints, weights, what, max_bind_mm)
    expect_rest_matches(pos * 1000.0 if static_mm is None else static_mm, rest_positions_mm(data["bones"], pos, joints, weights), what)
    return skel
