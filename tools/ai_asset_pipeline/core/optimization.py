"""Resolve Blender optimization profiles from config/optimization_profiles.json."""

from __future__ import annotations

import json
from pathlib import Path

from core.settings import PIPELINE_ROOT


def load_profiles(path: Path | None = None) -> dict:
    target = path or (PIPELINE_ROOT / "config" / "optimization_profiles.json")
    return json.loads(target.read_text(encoding="utf-8"))


def resolve_profile(
    profile_name: str,
    *,
    profiles: dict | None = None,
    defaults: dict | None = None,
    polycount_override: int | None = None,
) -> dict:
    table = profiles if profiles is not None else load_profiles()
    name = (profile_name or "prop").strip().lower() or "prop"
    base = dict(table.get(name) or table.get("prop") or {})
    defaults = defaults or {}
    target = polycount_override if polycount_override is not None else base.get("target_polycount")
    if target is None:
        target = defaults.get("character_polycount") if name in {"character", "enemy"} else defaults.get("polycount", 8000)
    lod = list(base.get("lod_ratios") if base.get("lod_ratios") is not None else defaults.get("lod_ratios") or [0.5, 0.25])
    return {
        "name": name if name in table else ("prop" if "prop" in table else name),
        "label": base.get("label") or name,
        "target_polycount": int(target),
        "lod_ratios": [float(value) for value in lod],
        "add_collision": bool(base.get("add_collision", True)),
        "recalc_normals": bool(base.get("recalc_normals", True)),
        "preserve_skin": bool(base.get("preserve_skin", False)),
        "skip_lod_if_skinned": bool(base.get("skip_lod_if_skinned", False)),
    }


def blender_job_fields(profile: dict) -> dict:
    return {
        "target_polycount": int(profile["target_polycount"]),
        "lod_ratios": list(profile.get("lod_ratios") or []),
        "add_collision": bool(profile.get("add_collision", True)),
        "recalc_normals": bool(profile.get("recalc_normals", True)),
        "preserve_skin": bool(profile.get("preserve_skin", False)),
        "skip_lod_if_skinned": bool(profile.get("skip_lod_if_skinned", False)),
        "optimization_profile": profile.get("name") or "",
    }
