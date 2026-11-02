"""Run inside Blender: blender --background --python process_mesh.py -- job.json

The job JSON uses input, output, result, target_polycount, lod_ratios, and recalc_normals.
This script does not delete the input file.
"""

import json
import sys
import traceback
from pathlib import Path

import bpy


def _job_path() -> Path:
    if "--" not in sys.argv:
        raise SystemExit("Pass the job json path after --")
    return Path(sys.argv[sys.argv.index("--") + 1])


def _mesh_objects():
    return [obj for obj in bpy.data.objects if obj.type == "MESH"]


def _triangle_count(obj) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def _apply_mesh(obj, target: int, recalc: bool) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    if recalc:
        bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    faces = _triangle_count(obj)
    if target and faces > target:
        modifier = obj.modifiers.new("PipelineDecimate", "DECIMATE")
        modifier.ratio = max(0.01, min(1.0, float(target) / float(faces)))
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def _combined_bounds():
    low = [1e9, 1e9, 1e9]
    high = [-1e9, -1e9, -1e9]
    found = False
    for obj in _mesh_objects():
        if obj.name.endswith("-colonly") or obj.name.endswith("-col"):
            continue
        found = True
        for corner in obj.bound_box:
            point = obj.matrix_world @ __import__("mathutils").Vector(corner)
            for axis in range(3):
                low[axis] = min(low[axis], point[axis])
                high[axis] = max(high[axis], point[axis])
    if not found:
        return None
    return low, high


def _ensure_collision() -> bool:
    for obj in _mesh_objects():
        if obj.name.endswith("-colonly") or obj.name.endswith("-col"):
            return False
    bounds = _combined_bounds()
    if bounds is None:
        return False
    low, high = bounds
    size = [max(high[axis] - low[axis], 0.01) for axis in range(3)]
    center = [(low[axis] + high[axis]) * 0.5 for axis in range(3)]
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    cube = bpy.context.active_object
    cube.name = "Collision-colonly"
    cube.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return True


def _export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=False)


def _duplicate_decimated(ratio: float, name: str):
    created = []
    for obj in list(_mesh_objects()):
        if obj.name.endswith("-colonly") or obj.name.endswith("-col"):
            continue
        copy = obj.copy()
        copy.data = obj.data.copy()
        copy.name = name
        bpy.context.collection.objects.link(copy)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = copy
        copy.select_set(True)
        modifier = copy.modifiers.new("LOD", "DECIMATE")
        modifier.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        created.append(copy)
    return created


def main() -> None:
    job_path = _job_path()
    job = json.loads(job_path.read_text(encoding="utf-8"))
    result_path = Path(job["result"])
    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=job["input"])
        if not _mesh_objects():
            raise RuntimeError("Blender imported no mesh objects.")
        target = int(job.get("target_polycount") or 0)
        for obj in _mesh_objects():
            _apply_mesh(obj, target, bool(job.get("recalc_normals", True)))
        missing_uv = [obj.name for obj in _mesh_objects() if not obj.data.uv_layers]
        collision_added = _ensure_collision()
        output = Path(job["output"])
        _export(output)
        lod_files = []
        for index, ratio in enumerate(job.get("lod_ratios") or [], start=1):
            created = _duplicate_decimated(float(ratio), f"LOD{index}")
            lod_path = output.with_name(f"lod{index}.glb")
            # Export only the LOD objects by hiding the others.
            hidden = []
            for obj in _mesh_objects():
                if obj not in created:
                    hidden.append((obj, obj.hide_render))
                    obj.hide_set(True)
            bpy.ops.export_scene.gltf(filepath=str(lod_path), export_format="GLB", use_visible=True)
            for obj, _previous in hidden:
                obj.hide_set(False)
            for obj in created:
                bpy.data.objects.remove(obj, do_unlink=True)
            lod_files.append(str(lod_path))
        triangles = sum(_triangle_count(obj) for obj in _mesh_objects() if not obj.name.endswith("-colonly"))
        result = {
            "ok": True,
            "output": str(output),
            "lod_files": lod_files,
            "collision_added": collision_added,
            "missing_uv": missing_uv,
            "triangles": triangles,
        }
    except Exception as exc:
        result = {"ok": False, "error": str(exc), "trace": traceback.format_exc()}
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    if not result["ok"]:
        raise SystemExit(result["error"])


if __name__ == "__main__":
    main()
