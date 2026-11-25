"""The asset manifest (asset.yaml): identity, stage, provenance and lineage of every image/mesh."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

CLASSES = ("creature", "prop", "architecture", "terrain", "interior", "kit")
STAGES = ("new", "concept", "locked", "turnaround", "brief", "to3d", "cleanup", "checked", "exported")
KINDS = ("concept", "turnaround", "mesh")
DECISIONS = ("approved", "rejected")


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


_PATH_KEYS = frozenset({"path", "report", "source"})
_PATH_LIST_KEYS = frozenset({"references", "images", "renders", "files"})


def _normalise_paths(node: Any, key: str = "") -> Any:
    """Stored paths use forward slashes; a manifest written with backslashes is rewritten on load."""
    if isinstance(node, dict):
        return {k: _normalise_paths(v, k) for k, v in node.items()}
    if isinstance(node, list):
        return [_normalise_paths(v, key) for v in node]
    if isinstance(node, str) and (key in _PATH_KEYS or key in _PATH_LIST_KEYS):
        return node.replace("\\", "/")
    return node


@dataclass
class LineageEntry:
    """One generated artifact. `parent` is the id of the entry it was derived from (refine, edit)."""
    id: str
    kind: str
    path: str
    provider: str
    model: str
    prompt: str = ""
    parent: str | None = None
    created: str = field(default_factory=now)
    writer: str = ""  # PromptWriter that composed the prompt, as name:model
    references: list[str] = field(default_factory=list)  # images passed to the provider
    reference: dict[str, str] = field(default_factory=dict)  # concept variants made from a reference: {name, sha256}
    mode: str = ""  # with a reference: paint-over or inspire
    presentation: str = ""  # concept variants: subject or scene (empty on manifests written before it existed)
    task_id: str = ""  # provider job id for a mesh run (image-to-3D)
    views: list[str] = field(default_factory=list)  # mesh runs: lineage ids of the turnaround views sent, in order
    options: dict[str, Any] = field(default_factory=dict)  # mesh runs: the model options sent in the request body
    source: dict[str, str] = field(default_factory=dict)  # imported meshes: {path, sha256} of the CAD export they came from


@dataclass
class Lock:
    variant: str
    decision: str
    reviewer: str
    notes: str = ""
    at: str = field(default_factory=now)


@dataclass
class BriefRecord:
    path: str
    writer: str
    model: str
    images: list[str] = field(default_factory=list)
    at: str = field(default_factory=now)


@dataclass
class CleanupRecord:
    """One cleanup run: what was cleaned, with which recipe and code, and what was measured."""
    id: str  # the cleaned mesh's lineage id
    source: str  # lineage id of the raw mesh
    recipe: list[str]
    params: dict[str, Any] = field(default_factory=dict)  # budget, size, palette size, grid
    commit: str = ""  # git commit of the pipeline code that ran it
    script_sha256: str = ""  # digest of the Blender script, so a dirty checkout is still identifiable
    blender: str = ""  # version string printed by the Blender that ran it
    runner: str = ""  # "native" or "docker"
    image: str = ""  # docker: image reference plus digest when the daemon reported it
    result: dict[str, Any] = field(default_factory=dict)  # measured triangles, non-manifold, colours, size
    at: str = field(default_factory=now)


@dataclass
class ImportRecord:
    """One `asset import`: the CAD export (repo-relative path and hash), the mesh it became and what was measured."""
    id: str  # the imported mesh's lineage id
    source: str  # repo-relative POSIX path of the copied export
    sha256: str
    parts: list[str] = field(default_factory=list)  # every part (mesh node) in the export, which a pivot may name
    pivot: str = ""  # the moving part's name; empty for a fixed part
    size_m: float = 0.0  # largest dimension of the converted mesh
    triangles: int = 0
    materials: dict[str, str] = field(default_factory=dict)  # material name in the export -> palette role
    commit: str = ""
    script_sha256: str = ""
    blender: str = ""
    runner: str = ""
    image: str = ""
    at: str = field(default_factory=now)


@dataclass
class PivotRecord:
    """A moving part of a kit asset: which part, its hinge axis and its limits in degrees from the rest pose."""
    part: str
    axis: str = "x"
    limits_deg: list[float] = field(default_factory=lambda: [-40.0, 40.0])
    control: str = "switch_lever"  # which control script `export` puts on the scene


@dataclass
class CheckRecord:
    """One `check` run: which mesh was gated, where the JSON report is, and which gates failed."""
    id: str  # the checked mesh's lineage id
    report: str  # repo-relative path of the JSON gate report
    ok: bool
    failed: list[str] = field(default_factory=list)
    at: str = field(default_factory=now)


@dataclass
class GodotCheckRecord:
    """One `godot-check` run: the mesh imported, the material check and where the game-lighting renders went."""
    id: str  # the imported mesh's lineage id
    ok: bool
    material: dict[str, Any] = field(default_factory=dict)
    renders: list[str] = field(default_factory=list)
    error: str = ""
    at: str = field(default_factory=now)


@dataclass
class ExportRecord:
    """One `export`: which mesh became the deliverable, and the files written (repo-relative)."""
    id: str
    files: list[str] = field(default_factory=list)
    commit: str = ""
    at: str = field(default_factory=now)


@dataclass
class CostRecord:
    """One paid backend call: usage as reported, USD, how the USD was arrived at, and the unit price used."""
    command: str
    stage: str
    provider: str
    model: str
    usd: float | None  # null when basis is `unknown`
    basis: str  # reported | estimated | mock | unknown | subscription
    lineage: str | None = None  # id of the lineage entry the call produced, if any
    units: dict[str, Any] = field(default_factory=dict)
    unit_price: dict[str, Any] = field(default_factory=dict)
    api_equivalent_usd: float | None = None  # claude-cli only; informational, never counted as spend
    error: str = ""  # set when the call failed but was billed
    at: str = field(default_factory=now)


@dataclass
class RenameRecord:
    """One `asset rename`: the slug before and after, and when. Lineage ids are never rewritten."""
    old: str
    new: str
    at: str = field(default_factory=now)


@dataclass
class Manifest:
    slug: str
    asset_class: str
    issue: int | None = None
    stage: str = "new"
    description: str = ""  # the concept brief: what the asset is, fed to the PromptWriter
    created: str = field(default_factory=now)
    lineage: list[LineageEntry] = field(default_factory=list)
    locked: Lock | None = None
    # Every decision, approvals and rejections, newest last. `locked` is the latest approval.
    decisions: list[Lock] = field(default_factory=list)
    brief: BriefRecord | None = None
    cleanups: list[CleanupRecord] = field(default_factory=list)
    checks: list[CheckRecord] = field(default_factory=list)
    godot_checks: list[GodotCheckRecord] = field(default_factory=list)
    exports: list[ExportRecord] = field(default_factory=list)
    imports: list[ImportRecord] = field(default_factory=list)  # kit (cad route): one per `asset import`
    pivots: list[PivotRecord] = field(default_factory=list)  # kit: the moving parts, from the latest import
    # The cost ledger (see cost.py): append-only, so reject, delete and regenerate never remove entries.
    costs: list[CostRecord] = field(default_factory=list)
    # Soft budget in USD for this asset; overrides the class's `budget_usd` in classes.yaml. Warns, never blocks.
    budget_usd: float | None = None
    renames: list[RenameRecord] = field(default_factory=list)

    def entry(self, entry_id: str) -> LineageEntry:
        for e in self.lineage:
            if e.id == entry_id:
                return e
        raise KeyError(f"no lineage entry {entry_id!r} in {self.slug}")

    def add(self, entry: LineageEntry) -> LineageEntry:
        if any(e.id == entry.id for e in self.lineage):
            raise ValueError(f"duplicate lineage id {entry.id!r}")
        if entry.kind not in KINDS:
            raise ValueError(f"unknown kind {entry.kind!r}")
        if entry.parent is not None:
            self.entry(entry.parent)  # must already exist, so lineage is acyclic
        self.lineage.append(entry)
        return entry

    def set_pivots(self, pivots: list[PivotRecord], parts: list[str] | None = None) -> None:
        """Record the moving parts. Each must name a part of the latest import (or of `parts`, when given)."""
        known = parts if parts is not None else (self.imports[-1].parts if self.imports else [])
        for p in pivots:
            if p.part not in known:
                raise ValueError(f"no part named {p.part!r} in the import; the parts are: {', '.join(known) or '(none)'}")
        self.pivots = list(pivots)

    def ancestry(self, entry_id: str) -> list[str]:
        """Ids from `entry_id` back to its root, nearest first."""
        chain: list[str] = []
        cur: str | None = entry_id
        while cur is not None:
            e = self.entry(cur)
            chain.append(e.id)
            cur = e.parent
        return chain

    def lock(self, variant: str, reviewer: str, decision: str = "approved", notes: str = "") -> Lock:
        e = self.entry(variant)
        if e.kind != "concept":
            raise ValueError(f"{variant!r} is a {e.kind}, only concept variants can be locked")
        if decision not in DECISIONS:
            raise ValueError(f"decision must be one of {DECISIONS}")
        rec = Lock(variant=variant, decision=decision, reviewer=reviewer, notes=notes)
        if decision == "approved":
            self.locked = rec
            self.stage = "locked"
        self.decisions.append(rec)
        return rec

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["class"] = d.pop("asset_class")
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Manifest":
        d = _normalise_paths(d)
        lock = d.get("locked")
        return cls(
            slug=d["slug"],
            asset_class=d["class"],
            issue=d.get("issue"),
            stage=d.get("stage", "new"),
            description=d.get("description", ""),
            created=d.get("created", now()),
            lineage=[LineageEntry(**e) for e in d.get("lineage") or []],
            locked=Lock(**lock) if lock else None,
            decisions=[Lock(**x) for x in d.get("decisions") or []],
            brief=BriefRecord(**d["brief"]) if d.get("brief") else None,
            cleanups=[CleanupRecord(**x) for x in d.get("cleanups") or []],
            checks=[CheckRecord(**x) for x in d.get("checks") or []],
            godot_checks=[GodotCheckRecord(**x) for x in d.get("godot_checks") or []],
            exports=[ExportRecord(**x) for x in d.get("exports") or []],
            imports=[ImportRecord(**x) for x in d.get("imports") or []],
            pivots=[PivotRecord(**x) for x in d.get("pivots") or []],
            costs=[CostRecord(**x) for x in d.get("costs") or []],
            budget_usd=d.get("budget_usd"),
            renames=[RenameRecord(**x) for x in d.get("renames") or []],
        )

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(self.to_dict(), sort_keys=False, allow_unicode=True))

    @classmethod
    def load(cls, path: Path) -> "Manifest":
        if not path.is_file():
            raise FileNotFoundError(f"no manifest at {path}")
        return cls.from_dict(yaml.safe_load(path.read_text()))
