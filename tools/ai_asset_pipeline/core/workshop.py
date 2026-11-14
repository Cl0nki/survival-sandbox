"""Workshop categories, production targets, and live counters."""

from __future__ import annotations

import json
from pathlib import Path

from core.settings import PIPELINE_ROOT


def load_workshop(path: Path | None = None) -> dict:
    target = path or (PIPELINE_ROOT / "config" / "workshop.json")
    return json.loads(target.read_text(encoding="utf-8"))


def category_ids(workshop: dict | None = None) -> list[str]:
    data = workshop or load_workshop()
    return list((data.get("categories") or {}).keys())


def resolve_category(workshop: dict, workshop_category: str) -> dict:
    categories = workshop.get("categories") or {}
    key = (workshop_category or "").strip().lower()
    if key not in categories:
        known = ", ".join(sorted(categories)) or "(none)"
        raise KeyError(f"Unknown workshop category '{workshop_category}'. Known: {known}")
    profile = dict(categories[key])
    profile["id"] = key
    return profile


def infer_workshop_category(asset: dict, workshop: dict | None = None) -> str:
    explicit = str((asset.get("workshop_category") or (asset.get("generation_parameters") or {}).get("workshop_category") or "")).strip().lower()
    if explicit:
        return explicit
    data = workshop or load_workshop()
    kind = str(asset.get("kind") or "").strip().lower()
    for key, profile in (data.get("categories") or {}).items():
        if profile.get("kind") == kind:
            return key
    if kind == "character":
        return "characters"
    if kind in {"prop", "building"}:
        folder = str((asset.get("generation_parameters") or {}).get("godot_folder") or "")
        if folder.startswith("deployable"):
            return "deployables"
        if folder.startswith("resource"):
            return "resources"
        if folder in {"environment", "props"}:
            return "decorations"
    return ""


def status_label(workshop: dict, status: str) -> str:
    labels = workshop.get("status_labels") or {}
    return labels.get(status, status.replace("_", " ").title())


def production_stats(store, project_root: Path, workshop: dict | None = None) -> dict:
    """Count approved production assets from library + pipeline_meta, not hard-coded."""
    data = workshop or load_workshop()
    targets = dict(data.get("production_targets") or {})
    categories = data.get("categories") or {}
    counted = {key: 0 for key in targets}
    in_progress = {key: 0 for key in targets}
    failed = {key: 0 for key in targets}
    pending_review = {key: 0 for key in targets}
    rejected = {key: 0 for key in targets}

    seen_names: set[str] = set()
    meta_dir = Path(project_root) / "assets" / "pipeline_meta"
    if meta_dir.is_dir():
        for path in meta_dir.glob("*.json"):
            if path.name.startswith("."):
                continue
            try:
                record = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            if record.get("approval_status") != "approved":
                continue
            category = infer_workshop_category(record, data)
            if category in counted and (categories.get(category) or {}).get("counts_toward_production", True):
                counted[category] += 1
                seen_names.add(str(record.get("asset_name") or path.stem))

    for asset in store.list_assets():
        category = infer_workshop_category(asset, data)
        if category not in targets:
            continue
        approval = asset.get("approval_status")
        processing = asset.get("processing_status")
        name = str(asset.get("asset_name") or "")
        if approval == "approved":
            if name and name not in seen_names and (categories.get(category) or {}).get("counts_toward_production", True):
                counted[category] += 1
                seen_names.add(name)
            continue
        if approval == "rejected":
            rejected[category] += 1
            continue
        if processing == "failed":
            failed[category] += 1
            continue
        if processing == "ready_for_review":
            pending_review[category] += 1
            continue
        if processing in {
            "waiting",
            "pending",
            "generating",
            "texturing",
            "rigging",
            "animating",
            "downloading",
            "processing",
            "validating",
        }:
            in_progress[category] += 1

    rows = []
    total_target = 0
    total_approved = 0
    for key, target in targets.items():
        approved = counted.get(key, 0)
        total_target += int(target)
        total_approved += approved
        rows.append(
            {
                "id": key,
                "label": (categories.get(key) or {}).get("label", key),
                "target": int(target),
                "approved": approved,
                "in_progress": in_progress.get(key, 0),
                "pending_review": pending_review.get(key, 0),
                "failed": failed.get(key, 0),
                "rejected": rejected.get(key, 0),
                "remaining": max(0, int(target) - approved),
            }
        )
    return {
        "targets": targets,
        "rows": rows,
        "totals": {
            "target": total_target,
            "approved": total_approved,
            "remaining": max(0, total_target - total_approved),
            "in_progress": sum(in_progress.values()),
            "pending_review": sum(pending_review.values()),
            "failed": sum(failed.values()),
            "rejected": sum(rejected.values()),
        },
    }
