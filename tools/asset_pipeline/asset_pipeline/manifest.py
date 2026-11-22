"""The asset manifest (asset.yaml): identity, stage, provenance and lineage of every image/mesh."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

CLASSES = ("creature", "prop", "architecture", "terrain")
STAGES = ("new", "concept", "locked", "turnaround", "brief", "to3d", "cleanup", "checked", "exported")
KINDS = ("concept", "turnaround", "mesh")
DECISIONS = ("approved", "rejected")


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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
    task_id: str = ""  # provider job id for a mesh run (image-to-3D)


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
class Manifest:
    slug: str
    asset_class: str
    issue: int | None = None
    stage: str = "new"
    description: str = ""  # the concept brief: what the asset is, fed to the PromptWriter
    created: str = field(default_factory=now)
    lineage: list[LineageEntry] = field(default_factory=list)
    locked: Lock | None = None
    # Decisions that did not lock (e.g. a rejection), newest last.
    decisions: list[Lock] = field(default_factory=list)
    brief: BriefRecord | None = None

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
        else:
            self.decisions.append(rec)
        return rec

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["class"] = d.pop("asset_class")
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Manifest":
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
        )

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(self.to_dict(), sort_keys=False, allow_unicode=True))

    @classmethod
    def load(cls, path: Path) -> "Manifest":
        if not path.is_file():
            raise FileNotFoundError(f"no manifest at {path}")
        return cls.from_dict(yaml.safe_load(path.read_text()))
