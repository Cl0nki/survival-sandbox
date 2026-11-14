import json
import subprocess
from pathlib import Path

from core.optimization import blender_job_fields, resolve_profile
from core.redact import redact
from core.settings import Settings

SCRIPT = Path(__file__).resolve().parent / "process_mesh.py"
CLOTHING_SCRIPT = Path(__file__).resolve().parent / "separate_clothing.py"


def blender_available(settings: Settings) -> bool:
    return bool(settings.blender_bin) and Path(settings.blender_bin).is_file()


def process_with_blender(
    settings: Settings,
    source_glb: Path,
    output_glb: Path,
    target_polycount: int,
    lod_ratios: list[float],
    log,
    *,
    profile_name: str = "",
    add_collision: bool | None = None,
    recalc_normals: bool = True,
    preserve_skin: bool = False,
    skip_lod_if_skinned: bool = False,
    target_size: list[float] | None = None,
) -> dict:
    if not blender_available(settings):
        return {
            "ok": False,
            "skipped": True,
            "message": "Blender was not found. Set BLENDER_BIN in tools/ai_asset_pipeline/.env. The original GLB was kept.",
        }
    profile = None
    if profile_name:
        profile = resolve_profile(
            profile_name,
            defaults=settings.defaults,
            polycount_override=target_polycount or None,
        )
        fields = blender_job_fields(profile)
        target_polycount = int(fields["target_polycount"])
        lod_ratios = list(fields["lod_ratios"])
        if add_collision is None:
            add_collision = bool(fields["add_collision"])
        recalc_normals = bool(fields["recalc_normals"])
        preserve_skin = bool(fields["preserve_skin"])
        skip_lod_if_skinned = bool(fields["skip_lod_if_skinned"])
    if add_collision is None:
        add_collision = True
    result_path = output_glb.with_suffix(".blender.json")
    job = {
        "input": str(source_glb),
        "output": str(output_glb),
        "result": str(result_path),
        "target_polycount": int(target_polycount),
        "lod_ratios": lod_ratios,
        "recalc_normals": bool(recalc_normals),
        "add_collision": bool(add_collision),
        "preserve_skin": bool(preserve_skin),
        "skip_lod_if_skinned": bool(skip_lod_if_skinned),
        "optimization_profile": (profile or {}).get("name") if profile else profile_name,
        "target_size": list(target_size) if target_size else None,
    }
    job_path = output_glb.with_suffix(".blender-job.json")
    job_path.write_text(json.dumps(job, indent=2), encoding="utf-8")
    command = [settings.blender_bin, "--background", "--python", str(SCRIPT), "--", str(job_path)]
    log("Running Blender: " + " ".join(command[:4]))
    completed = subprocess.run(command, capture_output=True, text=True, timeout=900, check=False)
    tail = redact((completed.stdout or "")[-2000:] + "\n" + (completed.stderr or "")[-2000:])
    log(tail)
    if result_path.is_file():
        result = json.loads(result_path.read_text(encoding="utf-8"))
    else:
        result = {"ok": False, "error": f"Blender exited {completed.returncode} without a result file.", "log": tail}
    result["returncode"] = completed.returncode
    result["job"] = job
    return result


def separate_clothing_with_blender(settings: Settings, source_glb: Path, plan: list[dict], body_mesh: str, log) -> dict:
    if not blender_available(settings):
        return {"ok": False, "skipped": True, "message": "Blender was not found for clothing separation."}
    result_path = source_glb.with_suffix(".clothing.json")
    job = {
        "input": str(source_glb),
        "result": str(result_path),
        "body_mesh": body_mesh,
        "pieces": plan,
    }
    job_path = source_glb.with_suffix(".clothing-job.json")
    job_path.write_text(json.dumps(job, indent=2), encoding="utf-8")
    command = [settings.blender_bin, "--background", "--python", str(CLOTHING_SCRIPT), "--", str(job_path)]
    log("Running Blender clothing: " + " ".join(command[:4]))
    completed = subprocess.run(command, capture_output=True, text=True, timeout=900, check=False)
    tail = redact((completed.stdout or "")[-2000:] + "\n" + (completed.stderr or "")[-2000:])
    log(tail)
    if result_path.is_file():
        result = json.loads(result_path.read_text(encoding="utf-8"))
    else:
        result = {"ok": False, "error": f"Blender clothing exited {completed.returncode}.", "log": tail}
    result["returncode"] = completed.returncode
    return result
