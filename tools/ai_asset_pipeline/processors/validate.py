import struct
from pathlib import Path

from processors.gltf_write import read_glb_json

GODOT_HUMANOID_BONES = (
    "Root",
    "Hips",
    "Spine",
    "Chest",
    "UpperChest",
    "Neck",
    "Head",
    "LeftUpperArm",
    "LeftLowerArm",
    "LeftHand",
    "RightUpperArm",
    "RightLowerArm",
    "RightHand",
    "LeftUpperLeg",
    "LeftLowerLeg",
    "LeftFoot",
    "RightUpperLeg",
    "RightLowerLeg",
    "RightFoot",
)

MANUAL_RIG_STEPS = [
    "Open the original GLB in Blender. The pipeline does not replace that file.",
    "Add an armature using the Godot humanoid bone names listed in the pipeline README.",
    "Keep a T-pose or A-pose and place the hips near the mesh pelvis.",
    "Parent the body mesh to the armature with automatic weights and fix the hands, feet, and head.",
    "Name clothing, helmets, and packs as separate meshes on the same skeleton when they should be swappable.",
    "Export glTF binary, Y-up, with the skin included.",
    "Upload that GLB with Reprocess in the dashboard. Validation runs again before anything can be approved.",
]


def _component_size(component_type: int) -> int:
    return {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[component_type]


def _type_count(type_name: str) -> int:
    return {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[type_name]


def inspect_glb(path: Path) -> dict:
    data = Path(path).read_bytes()
    document = read_glb_json(Path(path))
    meshes = document.get("meshes") or []
    nodes = document.get("nodes") or []
    materials = document.get("materials") or []
    accessors = document.get("accessors") or []
    skins = document.get("skins") or []
    images = document.get("images") or []
    triangles = 0
    has_uv = False
    has_normals = False
    bounds = None
    for mesh in meshes:
        if str(mesh.get("name", "")).endswith("-colonly") or str(mesh.get("name", "")).endswith("-col"):
            continue
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes") or {}
            if "TEXCOORD_0" in attributes:
                has_uv = True
            if "NORMAL" in attributes:
                has_normals = True
            position = attributes.get("POSITION")
            if position is not None and position < len(accessors):
                accessor = accessors[position]
                if "min" in accessor and "max" in accessor:
                    minimum = accessor["min"]
                    maximum = accessor["max"]
                    if bounds is None:
                        bounds = [list(minimum), list(maximum)]
                    else:
                        bounds[0] = [min(bounds[0][i], minimum[i]) for i in range(3)]
                        bounds[1] = [max(bounds[1][i], maximum[i]) for i in range(3)]
            index = primitive.get("indices")
            if index is not None and index < len(accessors):
                triangles += accessors[index]["count"] // 3
            elif position is not None and position < len(accessors):
                triangles += accessors[position]["count"] // 3
    joint_names = []
    for skin in skins:
        for joint in skin.get("joints", []):
            if 0 <= joint < len(nodes):
                joint_names.append(nodes[joint].get("name", f"joint_{joint}"))
    node_names = [node.get("name", "") for node in nodes]
    scales = []
    for node in nodes:
        if "scale" in node:
            scales.append(node["scale"])
    return {
        "bytes": len(data),
        "meshes": len(meshes),
        "materials": len(materials),
        "images": len(images),
        "triangles": triangles,
        "has_uv": has_uv,
        "has_normals": has_normals,
        "bounds": bounds,
        "skins": len(skins),
        "joint_names": joint_names,
        "node_names": node_names,
        "scales": scales,
        "has_collision_node": any(name.endswith("-colonly") or name.endswith("-col") for name in node_names),
        "generator": (document.get("asset") or {}).get("generator", ""),
    }


def validate_texture(paths: dict[str, Path], resolution: int) -> dict:
    errors = []
    warnings = []
    required = ("albedo", "normal", "roughness", "ao", "metallic")
    from PIL import Image

    size = None
    for name in required:
        path = paths.get(name)
        if path is None or not Path(path).is_file():
            errors.append(f"Missing {name} map.")
            continue
        if Path(path).stat().st_size < 32:
            errors.append(f"{name} map is empty.")
            continue
        with Image.open(path) as image:
            if image.size[0] != image.size[1]:
                errors.append(f"{name} map is not square.")
            if image.size[0] != resolution:
                errors.append(f"{name} map is {image.size[0]}px, expected {resolution}px.")
            if size is None:
                size = image.size
            elif image.size != size:
                errors.append(f"{name} map size does not match the albedo.")
    if "height" not in paths:
        warnings.append("Height map was not produced. It is optional.")
    return {"ok": not errors, "errors": errors, "warnings": warnings}


def validate_mesh(path: Path, kind: str, expect_collision: bool) -> dict:
    errors = []
    warnings = []
    report = {}
    file_path = Path(path)
    if not file_path.is_file() or file_path.stat().st_size < 20:
        return {"ok": False, "errors": ["GLB is missing or empty."], "warnings": [], "report": {}}
    try:
        report = inspect_glb(file_path)
    except (ValueError, KeyError, struct.error) as exc:
        return {"ok": False, "errors": [f"GLB is not readable: {exc}"], "warnings": [], "report": {}}
    if report["meshes"] < 1 or report["triangles"] < 1:
        errors.append("GLB does not contain a triangle mesh.")
    if report["materials"] < 1:
        errors.append("GLB does not contain a material.")
    if not report["has_uv"]:
        errors.append("Mesh has no TEXCOORD_0 UVs.")
    if not report["has_normals"]:
        errors.append("Mesh has no normals.")
    if report["triangles"] > 250000:
        errors.append(f"Polygon count is {report['triangles']}, above the 250000 triangle review limit.")
    for scale in report["scales"]:
        if any(abs(axis) < 1e-5 or abs(axis) > 100 for axis in scale):
            errors.append(f"Node scale {scale} is not a usable real-time scale.")
    bounds = report.get("bounds")
    if bounds is None:
        warnings.append("Position accessors have no bounds, so scale was not checked.")
    else:
        extents = [bounds[1][axis] - bounds[0][axis] for axis in range(3)]
        longest = max(extents)
        if longest > 40:
            warnings.append(f"Longest axis is {longest:.2f} m. Check the import scale before placing it.")
        if longest < 0.02:
            warnings.append(f"Longest axis is {longest:.3f} m. The mesh may be in centimeters or generic units.")
    if expect_collision and not report["has_collision_node"]:
        errors.append("No collision node named with the Godot -col or -colonly suffix.")
    if kind == "character":
        if report["skins"] < 1 or not report["joint_names"]:
            errors.append("Character GLB has no skin. Image-to-3D did not produce an animation-ready rig.")
        else:
            present = set(report["joint_names"])
            matched = [bone for bone in GODOT_HUMANOID_BONES if bone in present]
            if len(matched) < 8:
                warnings.append(
                    "The skeleton does not use Godot humanoid bone names. "
                    "Retarget it in Godot or rename the bones before sharing animations."
                )
    return {"ok": not errors, "errors": errors, "warnings": warnings, "report": report}
