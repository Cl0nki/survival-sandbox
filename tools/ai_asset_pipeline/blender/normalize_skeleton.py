"""Optional Blender pass: rename bones to Godot humanoid names.

blender --background --python normalize_skeleton.py -- job.json
"""

import json
import sys
from pathlib import Path

import bpy


def _job_path() -> Path:
    if "--" not in sys.argv:
        raise SystemExit("Pass the job json path after --")
    return Path(sys.argv[sys.argv.index("--") + 1])


def _clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def main() -> None:
    job = json.loads(_job_path().read_text(encoding="utf-8"))
    result = {"ok": False}
    try:
        _clear()
        bpy.ops.import_scene.gltf(filepath=job["input"])
        rename_map = {str(k).lower(): v for k, v in (job.get("rename_map") or {}).items()}
        renamed = 0
        for obj in bpy.data.objects:
            if obj.type != "ARMATURE":
                continue
            for bone in obj.data.bones:
                key = "".join(ch for ch in bone.name.lower() if ch.isalnum())
                target = rename_map.get(key)
                if target and target != bone.name:
                    bone.name = target
                    renamed += 1
        bpy.ops.export_scene.gltf(filepath=job["output"], export_format="GLB", use_selection=False)
        result = {"ok": True, "renamed_bones": renamed}
    except Exception as exc:  # noqa: BLE001 - surface to pipeline JSON
        result = {"ok": False, "error": str(exc)}
    Path(job["result"]).write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
