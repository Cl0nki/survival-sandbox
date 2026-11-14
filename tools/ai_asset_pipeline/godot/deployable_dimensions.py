"""Gameplay footprint/height for deployable Meshy jobs.

Mirrors scripts/deployables/* footprints. Placement still reads the GDScript
rules; this file only feeds workshop target_size and Ingame card labels.
"""

from __future__ import annotations

import json
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = PIPELINE_ROOT / "config" / "deployable_dimensions.json"


def load_dimensions(path: Path | None = None) -> dict:
    target = path or DEFAULT_PATH
    if not target.is_file():
        return {"cell_size": 1.0, "wall_thickness": 0.15, "edge_gap": 0.02, "defaults": {}, "items": {}}
    return json.loads(target.read_text(encoding="utf-8"))


def _clearance(config: dict) -> float:
    return float(config.get("wall_thickness", 0.15)) * 0.5 + float(config.get("edge_gap", 0.02))


def _opening_size(kind: str, entry: dict, config: dict) -> list[float]:
    cell = float(config.get("cell_size", 1.0))
    thick = float(config.get("wall_thickness", 0.15))
    span = cell - thick
    height = float(entry.get("height") or (2.2 if kind.startswith("door_") else 1.1))
    depth = thick * 0.5
    return [round(span, 4), round(height, 4), round(depth, 4)]


def _cell_body(entry: dict, config: dict) -> list[float]:
    footprint = entry.get("footprint") or [1, 1]
    width = max(int(footprint[0]), 1)
    depth = max(int(footprint[1]), 1)
    cell = float(config.get("cell_size", 1.0))
    pad = _clearance(config) * 2.0
    height = float(entry.get("height") or 0.84)
    return [
        round(width * cell - pad, 4),
        round(height, 4),
        round(depth * cell - pad, 4),
    ]


def dimensions_for(item_id: str, config: dict | None = None) -> dict | None:
    data = config if config is not None else load_dimensions()
    entry = (data.get("items") or {}).get(item_id)
    if not isinstance(entry, dict):
        return None
    footprint = [int(v) for v in (entry.get("footprint") or [0, 0])[:2]]
    while len(footprint) < 2:
        footprint.append(0)
    height = float(entry.get("height") or 0.0)
    opening = str(entry.get("opening") or "")
    if opening or footprint == [0, 0]:
        size = _opening_size(item_id, entry, data)
        mount = "opening"
    else:
        size = _cell_body(entry, data)
        mount = "cells"
    return {
        "footprint": footprint,
        "height": height,
        "opening": opening,
        "mount": mount,
        "target_size": size,
    }


def world_pickup_size(config: dict | None = None) -> list[float]:
    data = config if config is not None else load_dimensions()
    default = (data.get("defaults") or {}).get("world_pickup") or [0.38, 0.28, 0.38]
    return [float(default[0]), float(default[1]), float(default[2])]


def target_size_for_item(item_id: str, category: str, config: dict | None = None) -> list[float] | None:
    data = config if config is not None else load_dimensions()
    if category == "deployable":
        info = dimensions_for(item_id, data)
        return list(info["target_size"]) if info else None
    return world_pickup_size(data)
