#!/usr/bin/env python3
"""Generate Meshy walk-strafe clips (text-to-motion → animation on survivor rig).

Usage (from tools/ai_asset_pipeline):
  python scripts/generate_meshy_walk_strafe.py

Writes normalized GLBs under assets/characters/Shared/Quaternius/meshy_walk_strafe/
then expects tools/merge_meshy_walk_strafe.gd to pull them into ual_locomotion.res.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from core.settings import Settings  # noqa: E402
from processors.skeleton_normalize import load_skeleton_profile, normalize_glb_skeleton  # noqa: E402
from providers.http_client import download, request, request_json  # noqa: E402
from providers.meshy import ANIMATIONS, animation_payload  # noqa: E402
from providers.registry import meshy_from  # noqa: E402

TEXT_TO_MOTION = "https://api.meshy.ai/openapi/v1/text-to-motion"
PROJECT = ROOT.parents[1]
OUT_DIR = PROJECT / "assets" / "characters" / "Shared" / "Quaternius" / "meshy_walk_strafe"
META_PATH = OUT_DIR / "generation.json"

# workshop_survivor_01 Meshy rigging task (still valid while Meshy keeps the result).
DEFAULT_RIG_TASK_ID = "01a1a35d-7ed3-727c-bdc1-7836b812e802"

CLIPS = {
    "Idle": {
        "prompt": (
            "Loopable in-place humanoid standing idle. "
            "Facing camera-forward, upright relaxed posture, empty hands, no weapons, "
            "no props, subtle breathing and weight shift, feet planted, seamless loop."
        ),
        "duration": 2.5,
    },
    "Walk": {
        "prompt": (
            "Loopable in-place humanoid walking forward. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, casual walking gait (not jogging or running), "
            "natural arm swing, seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_L": {
        "prompt": (
            "Loopable in-place humanoid walking strafe to the character's left. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, steady side-step walk cycle, feet sliding sideways, "
            "arms swinging naturally, seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_R": {
        "prompt": (
            "Loopable in-place humanoid walking strafe to the character's right. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, steady side-step walk cycle, feet sliding sideways, "
            "arms swinging naturally, seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_Bwd": {
        "prompt": (
            "Loopable in-place humanoid walking backwards. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, careful backpedal walk cycle, arms swinging naturally, "
            "seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_Fwd_L": {
        "prompt": (
            "Loopable in-place humanoid walking diagonally forward-left. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, casual walking gait (not jogging or running), "
            "feet moving forward and left, arms swinging naturally, seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_Fwd_R": {
        "prompt": (
            "Loopable in-place humanoid walking diagonally forward-right. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, casual walking gait (not jogging or running), "
            "feet moving forward and right, arms swinging naturally, seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_Bwd_L": {
        "prompt": (
            "Loopable in-place humanoid walking diagonally backward-left. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, casual walking gait (not jogging or running), "
            "feet moving back and left, arms swinging naturally, seamless loop."
        ),
        "duration": 2.0,
    },
    "Walk_Bwd_R": {
        "prompt": (
            "Loopable in-place humanoid walking diagonally backward-right. "
            "Facing camera-forward the whole time, upright posture, relaxed empty hands, "
            "no weapons, no props, casual walking gait (not jogging or running), "
            "feet moving back and right, arms swinging naturally, seamless loop."
        ),
        "duration": 2.0,
    },
}


def _headers(key: str) -> dict:
    return {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def _poll(url: str, headers: dict, label: str, timeout_sec: int = 600, interval: float = 3.0) -> dict:
    deadline = time.monotonic() + timeout_sec
    while True:
        task = request("GET", url, headers, timeout=60).json()
        status = task.get("status", "")
        print(f"  {label}: {status} {task.get('progress', 0)}%")
        if status in {"SUCCEEDED", "FAILED", "CANCELED"}:
            if status != "SUCCEEDED":
                raise RuntimeError(f"{label} ended {status}: {json.dumps(task.get('task_error') or task)[:500]}")
            return task
        if time.monotonic() > deadline:
            raise TimeoutError(f"{label} timed out")
        time.sleep(interval)


def _create_motion(headers: dict, prompt: str, duration: float, mode: str = "prime") -> str:
    body = {"prompt": prompt, "duration": duration, "mode": mode}
    created = request_json("POST", TEXT_TO_MOTION, headers, body, timeout=60).json()
    task_id = created.get("result") or created.get("id")
    if not task_id:
        raise RuntimeError(f"text-to-motion create failed: {created}")
    return str(task_id)


def _create_animation(headers: dict, rig_task_id: str, motion_task_id: str) -> str:
    payload = animation_payload(rig_task_id, motion_task_id=motion_task_id)
    created = request_json("POST", ANIMATIONS, headers, payload, timeout=60).json()
    task_id = created.get("result") or created.get("id")
    if not task_id:
        raise RuntimeError(f"animation create failed: {created}")
    return str(task_id)


def main() -> int:
    settings = Settings()
    provider = meshy_from(settings)
    provider.require_key()
    headers = _headers(settings.meshy_key)
    balance = provider.get_balance()
    print("BALANCE=", balance.get("balance"))

    rig_task_id = DEFAULT_RIG_TASK_ID
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    profile = load_skeleton_profile(ROOT / "config" / "humanoid_skeleton.json")
    meta = {
        "rig_task_id": rig_task_id,
        "mode": "prime",
        "clips": {},
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    only = {a.strip() for a in (sys.argv[1:] if len(sys.argv) > 1 else []) if a.strip()}
    existing_meta = json.loads(META_PATH.read_text(encoding="utf-8")) if META_PATH.is_file() else {"clips": {}}
    meta["clips"] = dict(existing_meta.get("clips") or {})

    for alias, cfg in CLIPS.items():
        if only and alias not in only:
            continue
        norm_path = OUT_DIR / f"{alias}.glb"
        if not only and norm_path.is_file() and alias in meta["clips"]:
            print(f"SKIP existing {alias}")
            continue
        print(f"\n=== {alias} text-to-motion ===")
        motion_id = _create_motion(headers, cfg["prompt"], cfg["duration"], mode="prime")
        motion_task = _poll(f"{TEXT_TO_MOTION}/{motion_id}", headers, f"motion/{alias}")
        print(f"=== {alias} animation on rig ===")
        anim_id = _create_animation(headers, rig_task_id, motion_id)
        anim_task = _poll(f"{ANIMATIONS}/{anim_id}", headers, f"anim/{alias}")
        result = anim_task.get("result") or {}
        glb_url = result.get("animation_glb_url")
        if not glb_url:
            raise RuntimeError(f"{alias}: no animation_glb_url in {json.dumps(result)[:400]}")
        raw_path = OUT_DIR / f"{alias}_raw.glb"
        raw_path.write_bytes(download(glb_url))
        report = normalize_glb_skeleton(raw_path, norm_path, profile)
        meta["clips"][alias] = {
            "motion_task_id": motion_id,
            "animation_task_id": anim_id,
            "prompt": cfg["prompt"],
            "duration": cfg["duration"],
            "raw": str(raw_path.relative_to(PROJECT)).replace("\\", "/"),
            "normalized": str(norm_path.relative_to(PROJECT)).replace("\\", "/"),
            "normalize": {
                "renamed_bones": report.get("renamed_bones"),
                "missing_required": report.get("missing_required"),
            },
            "motion_url": (motion_task.get("result") or {}).get("motion_url"),
        }
        META_PATH.write_text(json.dumps(meta, indent=2), encoding="utf-8")
        print(f"WROTE {norm_path} renamed={report.get('renamed_bones')}")

    META_PATH.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print("\nMETA=", META_PATH)
    print("DONE clips=", sorted(meta["clips"].keys()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
