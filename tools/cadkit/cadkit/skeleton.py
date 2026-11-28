"""Skeletons for generated organic scenes: named bones, chains laid along a curve, and per-vertex skin bindings.

Bones live in the solids' frame (millimetres). A bone is a head, a tail and a parent; at rest every bone has an identity
rotation, so a joint node sits at its bone's head and its inverse bind matrix is a translation by minus that head.

A solid is bound before `solids.surfaces` merges solids per role, so each vertex keeps its own binding through the merge:
  Rigid(bone)      the whole solid follows one bone (a fin, an eye, a gill plate);
  Chain([bones])   each vertex is projected onto the chain and blended linearly between the two nearest bones.
Weights are at most four influences per vertex, normalised to sum to 1.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

MAX_INFLUENCES = 4


@dataclass(frozen=True)
class Bone:
    name: str
    head: tuple[float, float, float]
    tail: tuple[float, float, float]
    parent: str | None = None


@dataclass(frozen=True)
class Rigid:
    bone: str


@dataclass(frozen=True)
class Chain:
    bones: tuple[str, ...]

    def __init__(self, bones):
        object.__setattr__(self, "bones", tuple(bones))


@dataclass
class Skeleton:
    bones: list[Bone] = field(default_factory=list)

    def __post_init__(self):
        seen: set[str] = set()
        for b in self.bones:
            if b.name in seen:
                raise ValueError(f"duplicate bone {b.name!r}")
            if b.parent is not None and b.parent not in seen:
                raise ValueError(f"bone {b.name!r}: parent {b.parent!r} must be listed before it")
            seen.add(b.name)

    def names(self) -> list[str]:
        return [b.name for b in self.bones]

    def index(self, name: str) -> int:
        for i, b in enumerate(self.bones):
            if b.name == name:
                return i
        raise KeyError(f"no bone {name!r}: {self.names()}")

    def bone(self, name: str) -> Bone:
        return self.bones[self.index(name)]

    def weights(self, binding, pos_mm: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """(joints (n, 4) uint16, weights (n, 4) float32) for vertices at pos_mm (n, 3), per the binding."""
        n = len(pos_mm)
        full = np.zeros((n, len(self.bones)))
        if isinstance(binding, Rigid):
            full[:, self.index(binding.bone)] = 1.0
        elif isinstance(binding, Chain):
            full[:, [self.index(b) for b in binding.bones]] = chain_weights(
                np.array([self.bone(b).head for b in binding.bones]), self.bone(binding.bones[-1]).tail, pos_mm)
        else:
            raise TypeError(f"not a binding: {binding!r}")
        return limit_influences(full)


def lay_chain(prefix: str, points, n: int, parent: str | None = None) -> list[Bone]:
    """N bones of equal length along a polyline (mm), named `<prefix>0`..; the first is parented to `parent`, each
    next one to the one before. Each bone's tail is the next one's head."""
    pts = np.asarray(points, dtype=float)
    if n < 1 or len(pts) < 2:
        raise ValueError("a chain needs at least one bone and a polyline of at least two points")
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    if cum[-1] <= 0:
        raise ValueError("the polyline has no length")
    stops = np.linspace(0.0, cum[-1], n + 1)
    joints = np.stack([np.interp(stops, cum, pts[:, k]) for k in range(3)], axis=1)
    return [Bone(f"{prefix}{i}", tuple(float(x) for x in joints[i]), tuple(float(x) for x in joints[i + 1]),
                 parent if i == 0 else f"{prefix}{i - 1}") for i in range(n)]


def chain_weights(heads: np.ndarray, end: tuple[float, float, float], pos_mm: np.ndarray) -> np.ndarray:
    """(n, bones) weights along a chain whose bones start at `heads` and whose last bone ends at `end`.
    A vertex is projected to its nearest point on the joint polyline; at bone k's head it is entirely bone k,
    between heads k and k+1 it blends k and k+1 linearly, and past either end it is the end bone's."""
    line = np.vstack([heads, np.asarray(end, dtype=float)[None]])
    a, b = line[:-1], line[1:]
    d = b - a
    seg_len = np.linalg.norm(d, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg_len)])
    p = np.asarray(pos_mm, dtype=float)
    rel = p[:, None, :] - a[None]
    t = np.clip(np.einsum("nsk,sk->ns", rel, d) / np.maximum(seg_len ** 2, 1e-12), 0.0, 1.0)
    dist = np.linalg.norm(rel - t[..., None] * d[None], axis=2)
    best = dist.argmin(axis=1)
    rows = np.arange(len(p))
    s = cum[best] + t[rows, best] * seg_len[best]
    k = len(heads)
    w = np.zeros((len(p), k))
    head_s = cum[:k]
    for i in range(k - 1):
        m = (s >= head_s[i]) & (s <= head_s[i + 1])
        f = (s[m] - head_s[i]) / max(head_s[i + 1] - head_s[i], 1e-12)
        w[m, i] = 1.0 - f
        w[m, i + 1] = f
    w[s < head_s[0], 0] = 1.0
    w[s > head_s[-1], k - 1] = 1.0
    return w


def limit_influences(full: np.ndarray, limit: int = MAX_INFLUENCES) -> tuple[np.ndarray, np.ndarray]:
    """Keep each row's `limit` largest weights and renormalise: (joints (n, limit) uint16, weights (n, limit) float32).
    Unused slots are joint 0 with weight 0."""
    full = np.asarray(full, dtype=float)
    order = np.argsort(-full, axis=1, kind="stable")[:, :limit]
    w = np.take_along_axis(full, order, axis=1)
    w = np.where(w > 0, w, 0.0)
    tot = w.sum(axis=1, keepdims=True)
    if np.any(tot <= 0):
        raise ValueError("a vertex has no bone influence")
    w = w / tot
    order = np.where(w > 0, order, 0)
    if order.shape[1] < limit:
        pad = limit - order.shape[1]
        order = np.pad(order, ((0, 0), (0, pad)))
        w = np.pad(w, ((0, 0), (0, pad)))
    return order.astype(np.uint16), w.astype(np.float32)


def skin_positions(skel: Skeleton, joints: np.ndarray, weights: np.ndarray, pos_mm: np.ndarray,
                   rotations: dict[str, np.ndarray] | None = None) -> np.ndarray:
    """Linear blend skinning of vertices (mm) with each named bone rotated by a 3x3 matrix about its head, on top of its
    parent's pose. No rotations is the rest pose, which returns pos_mm."""
    rotations = rotations or {}
    world: dict[str, tuple[np.ndarray, np.ndarray]] = {}  # name -> (R, t): world pose as p' = R p + t, from rest
    for b in skel.bones:
        h = np.array(b.head, dtype=float)
        pr, pt = world[b.parent] if b.parent else (np.eye(3), np.zeros(3))
        local = np.asarray(rotations.get(b.name, np.eye(3)), dtype=float)
        # rotate about the head, whose posed position is the parent's transform of it
        r = pr @ local
        t = (pr @ h + pt) - r @ h
        world[b.name] = (r, t)
    out = np.zeros((len(pos_mm), 3))
    p = np.asarray(pos_mm, dtype=float)
    for slot in range(joints.shape[1]):
        for j in np.unique(joints[:, slot]):
            m = (joints[:, slot] == j) & (weights[:, slot] > 0)
            if m.any():
                r, t = world[skel.bones[int(j)].name]
                out[m] += weights[m, slot, None] * (p[m] @ r.T + t)
    return out
