"""Run inside Blender: separate named clothing meshes and transfer weights from body.

blender --background --python separate_clothing.py -- job.json
"""

from __future__ import annotations

import json
import sys
import traceback
from pathlib import Path

import bpy


def _job_path() -> Path:
    if "--" not in sys.argv:
        raise SystemExit("Pass the job json path after --")
    return Path(sys.argv[sys.argv.index("--") + 1])


def _find_object(name: str):
    for obj in bpy.data.objects:
        if obj.name == name or obj.name.lower() == name.lower():
            return obj
    return None


def _export_selected(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True)


def _transfer_weights(source, target) -> bool:
    if source is None or target is None:
        return False
    if source.type != "MESH" or target.type != "MESH":
        return False
    armature = None
    for modifier in source.modifiers:
        if modifier.type == "ARMATURE" and modifier.object:
            armature = modifier.object
            break
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    try:
        bpy.ops.object.data_transfer(
            use_reverse_transfer=False,
            data_type="VGROUP_WEIGHTS",
            layers_select_src="ALL",
            layers_select_dst="NAME",
            mix_mode="REPLACE",
        )
    except Exception:
        return False
    if armature is not None:
        existing = [modifier for modifier in target.modifiers if modifier.type == "ARMATURE"]
        if not existing:
            modifier = target.modifiers.new("Armature", "ARMATURE")
            modifier.object = armature
    return True


def main() -> None:
    job_path = _job_path()
    job = json.loads(job_path.read_text(encoding="utf-8"))
    result_path = Path(job["result"])
    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=job["input"])
        body_name = job.get("body_mesh") or "Body"
        body = _find_object(body_name)
        exported = []
        for piece in job.get("pieces") or []:
            mesh_name = piece.get("mesh_name") or ""
            output = Path(piece["output"])
            obj = _find_object(mesh_name)
            if obj is None:
                continue
            if body is not None and obj != body:
                _transfer_weights(body, obj)
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            _export_selected(output)
            exported.append(
                {
                    "slot": piece.get("slot"),
                    "mesh_name": obj.name,
                    "output": str(output),
                    "attach_bone": piece.get("attach_bone") or "",
                }
            )
        result = {"ok": True, "exported": exported, "body_mesh": body.name if body else ""}
    except Exception as exc:
        result = {"ok": False, "error": str(exc), "trace": traceback.format_exc()}
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    if not result.get("ok"):
        raise SystemExit(result.get("error") or "clothing separation failed")


if __name__ == "__main__":
    main()
