"""The mounting rule: a station sets an instanced kit scene off its host face by MOUNT_GAP_MM.

A kit scene's back sits on its own Z=0 (or `depth_mm.behind_origin` behind it), so one set flush on a host face has a
back face coplanar with the host and the two flicker (z-fight). The rule: the station instances it with its anchor
MOUNT_GAP_MM out of the host face (`stand_off`), and declares each such mount in its entry (`mounts`, built with
`record`). `cadkit verify` (and every build) fails a station that declares a mount with a face within
COPLANAR_TOL_MM of the host face. The check reads `component.yaml` depths, never the GLBs. A station with no `mounts`
key has not opted in and is not checked yet (docs/asset_process.md, 5.1).
"""
from __future__ import annotations

from typing import Callable

MOUNT_GAP_MM = 2.0        # how far a station sets an instanced kit scene off its host face
COPLANAR_TOL_MM = 0.5     # a face this close to the host face (or nearer) counts as coplanar


def stand_off(out_mm: float = 0.0) -> float:
    """The anchor's offset out of the host face (mm) for a scene meant to sit `out_mm` out of it, plus the gap."""
    return out_mm + MOUNT_GAP_MM


def record(anchor: str, slug: str, offset_mm: float, host_face: str = "") -> dict:
    """One `mounts` item for the station's entry: the anchor node, the kit scene on it, and the anchor's offset (mm)
    out of the host face along its normal. `host_face` names the face (a label for the message)."""
    return {"anchor": anchor, "scene": slug, "offset_mm": round(float(offset_mm), 3), "host_face": host_face}


def problems(station: str, station_entry: dict, entry_of: Callable[[str], dict]) -> list[str]:
    """Messages for each declared mount of a station that has a face within the tolerance of its host face."""
    out = []
    for m in station_entry.get("mounts") or []:
        depth = entry_of(m["scene"]).get("depth_mm")
        if depth is None:
            stand = entry_of(m["scene"]).get("stand_out_mm", 0.0)
            depth = {"behind_origin": 0.0, "in_front_of_origin": stand}
        faces = {"back": m["offset_mm"] - depth["behind_origin"], "front": m["offset_mm"] + depth["in_front_of_origin"]}
        for name, z in faces.items():
            if abs(z) <= COPLANAR_TOL_MM:
                out.append(f"{station}: anchor {m['anchor']} ({m['scene']}, offset {m['offset_mm']} mm, depth behind "
                           f"{depth['behind_origin']} mm, in front {depth['in_front_of_origin']} mm) puts its {name} "
                           f"face {z:+.2f} mm from the host face{' ' + m['host_face'] if m.get('host_face') else ''}; "
                           f"within {COPLANAR_TOL_MM} mm. Set it off by MOUNT_GAP_MM ({MOUNT_GAP_MM} mm): mount.stand_off()")
    return out
